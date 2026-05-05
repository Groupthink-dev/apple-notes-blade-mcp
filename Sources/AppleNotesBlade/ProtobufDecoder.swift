import Foundation
import Compression

/// Hand-rolled decoder for Apple Notes' on-disk note bodies.
///
/// **Format:** `ZICNOTEDATA.ZDATA` is a gzip-compressed protobuf blob. The outer
/// envelope is `NoteStoreProto`; the actual note text lives several layers deep
/// (`document.version[].note.note_text`) and varies in shape across macOS
/// versions. Rather than codegen a brittle proto schema, we walk the wire
/// format directly with bounded recursion and extract the longest UTF-8
/// "readable text" string we can find.
///
/// **Why heuristic and not strict schema:** Apple's proto layout has shifted
/// across macOS releases, and many fields are optional / version-tagged. A
/// strict decoder breaks on the first schema bump; the heuristic walker
/// degrades gracefully to "got something readable" instead of "got nothing"
/// when an unknown field shape appears. Trade-off: occasional false positives
/// (extracting a field that isn't quite the body). Soak time will tell us how
/// much that matters in practice.
///
/// **Hardening:** bounded recursion (`maxDepth`), bounded message size
/// (`maxMessageBytes`), bounded varint length (`maxVarintBytes`). Every parse
/// failure throws `NotesBladeError.decodeFailure(noteID:reason:)` carrying the
/// note ID for correlation but never the body.
public struct ProtobufNotesDecoder: Sendable {

    /// Max nesting depth when recursively decoding length-delimited fields as
    /// embedded messages. 32 is well beyond what Apple Notes actually nests.
    public static let maxDepth: Int = 32

    /// Hard cap on the inflated payload size (post-gunzip). 16 MB easily
    /// covers any plausible note (Apple's UI complains around 100 KB).
    public static let maxMessageBytes: Int = 16 * 1024 * 1024

    /// Max bytes a single varint can occupy. Spec says 10 (for 64-bit varints);
    /// we enforce that.
    public static let maxVarintBytes: Int = 10

    /// Note ID used in error messages. Carries no body content.
    public let noteID: Int64

    public init(noteID: Int64) {
        self.noteID = noteID
    }

    // MARK: - Public entry point

    /// Decode a ZDATA blob into the note's plain text + attachment metadata.
    /// Throws `NotesBladeError.decodeFailure` on any parse failure; never
    /// returns garbage to the caller.
    public func decode(zdata: Data) throws -> DecodedNote {
        guard !zdata.isEmpty else {
            throw NotesBladeError.decodeFailure(noteID: noteID, reason: "empty zdata blob")
        }
        let inflated = try gunzip(zdata)
        guard inflated.count <= Self.maxMessageBytes else {
            throw NotesBladeError.decodeFailure(
                noteID: noteID,
                reason: "inflated payload exceeds \(Self.maxMessageBytes) bytes"
            )
        }

        var strings: [String] = []
        var attachmentIDs: [String] = []
        try walk(payload: inflated, depth: 0, strings: &strings, attachmentIDs: &attachmentIDs)

        let plainText = pickBody(from: strings)
        let attachments = attachmentIDs.map { id in
            DecodedAttachmentMeta(identifier: id, typeUTI: nil)
        }
        return DecodedNote(plainText: plainText, attachments: attachments)
    }

    // MARK: - Gzip / deflate

    /// Strip the gzip envelope and decompress the inner deflate stream using
    /// Apple's `Compression` framework. Returns the inflated payload.
    private func gunzip(_ data: Data) throws -> Data {
        // Magic check
        guard data.count >= 18 else {
            throw NotesBladeError.decodeFailure(noteID: noteID, reason: "gzip blob too short")
        }
        guard data[0] == 0x1f, data[1] == 0x8b else {
            throw NotesBladeError.decodeFailure(noteID: noteID, reason: "missing gzip magic")
        }
        let flg = data[3]
        var offset = 10  // fixed header

        // FEXTRA — variable-length extra field
        if flg & 0x04 != 0 {
            guard offset + 2 <= data.count else {
                throw NotesBladeError.decodeFailure(noteID: noteID, reason: "truncated FEXTRA length")
            }
            let xlen = Int(data[offset]) | (Int(data[offset + 1]) << 8)
            offset += 2 + xlen
        }
        // FNAME — null-terminated filename
        if flg & 0x08 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FCOMMENT — null-terminated comment
        if flg & 0x10 != 0 {
            while offset < data.count, data[offset] != 0 { offset += 1 }
            offset += 1
        }
        // FHCRC — header CRC16
        if flg & 0x02 != 0 {
            offset += 2
        }
        guard offset < data.count - 8 else {
            throw NotesBladeError.decodeFailure(noteID: noteID, reason: "gzip header longer than data")
        }
        let payloadEnd = data.count - 8  // strip 8-byte trailer
        let payload = data.subdata(in: offset..<payloadEnd)

        // Decompress raw deflate via Compression framework.
        // Initial buffer = 10x compressed size; expand on overflow.
        let initialCapacity = max(payload.count * 10, 4096)
        let inflated = try inflateDeflate(payload, initialCapacity: initialCapacity)
        return inflated
    }

    /// Decompress raw-deflate bytes via `compression_decode_buffer`. The
    /// buffer is sized aggressively up-front; overflow expands once and
    /// retries before giving up.
    private func inflateDeflate(_ payload: Data, initialCapacity: Int) throws -> Data {
        var capacity = initialCapacity
        for _ in 0..<3 {
            if capacity > Self.maxMessageBytes {
                throw NotesBladeError.decodeFailure(
                    noteID: noteID,
                    reason: "deflate output exceeds maxMessageBytes"
                )
            }
            let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
            defer { dest.deallocate() }
            let count = payload.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
                guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    dest, capacity, base, payload.count, nil, COMPRESSION_ZLIB
                )
            }
            if count == 0 {
                throw NotesBladeError.decodeFailure(noteID: noteID, reason: "deflate decode returned 0")
            }
            // If `count == capacity` we likely truncated; expand and retry.
            if count == capacity {
                capacity *= 4
                continue
            }
            return Data(bytes: dest, count: count)
        }
        throw NotesBladeError.decodeFailure(noteID: noteID, reason: "deflate buffer expansion exhausted")
    }

    // MARK: - Wire-format walker

    /// Recursively walk a protobuf-encoded payload, collecting any
    /// length-delimited field whose payload either:
    ///   - decodes as a "readable" UTF-8 string (added to `strings`)
    ///   - looks like an Apple Notes attachment identifier (added to `attachmentIDs`)
    ///
    /// Length-delimited fields are also recursively walked as embedded
    /// messages — this is how we reach text that's wrapped in two or three
    /// layers of envelope without knowing the exact schema.
    ///
    /// `depth` is the recursion budget. Throws `decodeFailure` on truncation
    /// or unknown wire-type, never silently drops data.
    private func walk(
        payload: Data,
        depth: Int,
        strings: inout [String],
        attachmentIDs: inout [String]
    ) throws {
        guard depth < Self.maxDepth else {
            throw NotesBladeError.decodeFailure(noteID: noteID, reason: "max depth \(Self.maxDepth) exceeded")
        }

        var offset = payload.startIndex
        while offset < payload.endIndex {
            let header = try readVarint(payload, &offset)
            let wireType = Int(header & 0x07)

            switch wireType {
            case 0:  // varint
                _ = try readVarint(payload, &offset)

            case 1:  // fixed64
                guard offset + 8 <= payload.endIndex else {
                    throw NotesBladeError.decodeFailure(noteID: noteID, reason: "truncated fixed64")
                }
                offset += 8

            case 2:  // length-delimited
                let len = Int(try readVarint(payload, &offset))
                guard len >= 0, offset + len <= payload.endIndex else {
                    throw NotesBladeError.decodeFailure(noteID: noteID, reason: "truncated length-delimited")
                }
                let inner = payload.subdata(in: offset..<(offset + len))
                offset += len
                processLengthDelimited(
                    inner, depth: depth, strings: &strings, attachmentIDs: &attachmentIDs
                )

            case 5:  // fixed32
                guard offset + 4 <= payload.endIndex else {
                    throw NotesBladeError.decodeFailure(noteID: noteID, reason: "truncated fixed32")
                }
                offset += 4

            case 3, 4:  // deprecated start_group / end_group
                throw NotesBladeError.decodeFailure(
                    noteID: noteID, reason: "unsupported group wire type \(wireType)"
                )

            default:
                throw NotesBladeError.decodeFailure(
                    noteID: noteID, reason: "unknown wire type \(wireType)"
                )
            }
        }
    }

    /// Process a single length-delimited blob: try to decode as UTF-8 string,
    /// try to recurse as an embedded message. Either or both may succeed; we
    /// gather everything we find.
    private func processLengthDelimited(
        _ inner: Data,
        depth: Int,
        strings: inout [String],
        attachmentIDs: inout [String]
    ) {
        // String extraction — only keep "readable" text of meaningful length.
        if let str = String(data: inner, encoding: .utf8), Self.looksLikeReadableText(str) {
            strings.append(str)
            // Apple Notes attachments are referenced by UUID strings of the
            // shape "F4DCEC4A-...". Capture those for the attachment list.
            if Self.looksLikeAttachmentIdentifier(str) {
                attachmentIDs.append(str)
            }
        }
        // Recursive descent — even if it parsed as a string, it may also
        // parse as an embedded message (rare, but harmless).
        var inner_strings: [String] = []
        var inner_attachments: [String] = []
        try? walk(
            payload: inner,
            depth: depth + 1,
            strings: &inner_strings,
            attachmentIDs: &inner_attachments
        )
        strings.append(contentsOf: inner_strings)
        attachmentIDs.append(contentsOf: inner_attachments)
    }

    // MARK: - Heuristics

    /// Does this string look like genuine human-readable text? Filters out
    /// random-byte-soup that happens to round-trip through UTF-8.
    ///
    /// **Wire-format leak guard:** envelope bytes (field tags + length
    /// varints) for low field numbers all fall in U+0001..U+001F. Genuine
    /// human prose never starts with such a byte. So we additionally require
    /// that the *first* scalar is either printable (≥ U+0020) or one of
    /// `\t \n \r`. This kills the common false positive where a multi-byte
    /// envelope's bytes happen to all be ASCII-printable below 128.
    static func looksLikeReadableText(_ s: String) -> Bool {
        guard s.count >= 3 else { return false }
        // Reject if any embedded NUL.
        if s.contains("\0") { return false }

        // First-scalar gate.
        guard let first = s.unicodeScalars.first else { return false }
        if first.value < 0x20 && first != "\t" && first != "\n" && first != "\r" {
            return false
        }

        // At least 70% of unicode scalars must be printable (≥ U+0020) or
        // common whitespace (\t \n \r). Anything below that is a strong
        // signal we're staring at struct bytes, not text.
        var printable = 0
        var total = 0
        for scalar in s.unicodeScalars {
            total += 1
            if scalar.value >= 0x20 || scalar == "\t" || scalar == "\n" || scalar == "\r" {
                printable += 1
            }
        }
        guard total > 0 else { return false }
        return Double(printable) / Double(total) >= 0.7
    }

    /// Cheap signature for the canonical Apple attachment identifier shape:
    /// 36-char UUID (`8-4-4-4-12` hex with hyphens). False positives are
    /// rare and harmless — they get filtered by the consuming skill.
    static func looksLikeAttachmentIdentifier(_ s: String) -> Bool {
        guard s.count == 36 else { return false }
        let parts = s.split(separator: "-")
        let expectedLengths = [8, 4, 4, 4, 12]
        guard parts.count == expectedLengths.count else { return false }
        for (i, part) in parts.enumerated() {
            guard part.count == expectedLengths[i] else { return false }
            for c in part {
                guard c.isHexDigit else { return false }
            }
        }
        return true
    }

    /// Pick the most-likely body string from the collected candidates.
    ///
    /// V0.1.0 strategy: longest readable string wins. Apple attachment
    /// identifiers and other UUID-shaped strings are dropped from
    /// consideration regardless of length. Empty-or-short results return "".
    private func pickBody(from strings: [String]) -> String {
        let candidates = strings.filter { !Self.looksLikeAttachmentIdentifier($0) && $0.count >= 3 }
        return candidates.max(by: { $0.count < $1.count }) ?? ""
    }

    // MARK: - Varints

    /// Read a base-128 varint from `payload` starting at `offset`. Advances
    /// `offset` past the varint on success.
    private func readVarint(_ payload: Data, _ offset: inout Data.Index) throws -> UInt64 {
        var result: UInt64 = 0
        var shift: UInt64 = 0
        var bytesRead = 0
        while offset < payload.endIndex {
            let byte = payload[offset]
            offset += 1
            bytesRead += 1
            result |= UInt64(byte & 0x7f) << shift
            if byte & 0x80 == 0 {
                return result
            }
            shift += 7
            if bytesRead >= Self.maxVarintBytes {
                throw NotesBladeError.decodeFailure(
                    noteID: noteID,
                    reason: "varint exceeds \(Self.maxVarintBytes) bytes"
                )
            }
        }
        throw NotesBladeError.decodeFailure(noteID: noteID, reason: "truncated varint")
    }
}

// MARK: - Decoded shapes

public struct DecodedNote: Sendable, Equatable {
    public let plainText: String
    public let attachments: [DecodedAttachmentMeta]
}

public struct DecodedAttachmentMeta: Sendable, Equatable {
    public let identifier: String?
    public let typeUTI: String?
}
