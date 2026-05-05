import Foundation
import Compression
@testable import AppleNotesBlade

/// Builds synthetic ZDATA blobs (gzip-compressed protobuf) for tests.
///
/// We don't replicate Apple's real proto schema. We build a minimal "looks
/// like Apple Notes" envelope that contains a known body string so the
/// decoder's heuristic walker has something to extract. The decoder doesn't
/// care about field numbers or nesting depth; it walks anything length-
/// delimited and grabs the longest readable string.
enum ProtobufFixtures {

    /// Build a ZDATA blob containing `body` as the longest embedded string.
    /// The wrapping shape mimics Apple Notes' multi-layered envelope by
    /// nesting the body inside two embedded message fields.
    static func makeNoteBody(_ body: String, attachmentUUID: String? = nil) -> Data {
        // Inner message: { field 2 (length-delimited) = body string }
        var inner = Data()
        inner.append(encodeFieldHeader(fieldNumber: 2, wireType: 2))
        inner.append(encodeLengthDelimited(Data(body.utf8)))

        if let uuid = attachmentUUID {
            inner.append(encodeFieldHeader(fieldNumber: 1, wireType: 2))
            inner.append(encodeLengthDelimited(Data(uuid.utf8)))
        }

        // Middle message: { field 3 (length-delimited) = inner }
        var middle = Data()
        middle.append(encodeFieldHeader(fieldNumber: 3, wireType: 2))
        middle.append(encodeLengthDelimited(inner))

        // Outer message: { field 2 (length-delimited) = middle }
        var outer = Data()
        outer.append(encodeFieldHeader(fieldNumber: 2, wireType: 2))
        outer.append(encodeLengthDelimited(middle))

        return gzipCompress(outer)
    }

    /// Build a ZDATA blob with a deeply-nested body string to exercise the
    /// recursion budget. `depth` controls how many message envelopes wrap
    /// the body.
    static func makeDeeplyNestedBody(_ body: String, depth: Int) -> Data {
        var current = Data()
        current.append(encodeFieldHeader(fieldNumber: 2, wireType: 2))
        current.append(encodeLengthDelimited(Data(body.utf8)))
        for _ in 0..<depth {
            var wrapper = Data()
            wrapper.append(encodeFieldHeader(fieldNumber: 3, wireType: 2))
            wrapper.append(encodeLengthDelimited(current))
            current = wrapper
        }
        return gzipCompress(current)
    }

    /// Random-byte payload (NOT gzip) for negative-path testing.
    static func makeNonGzipBlob() -> Data {
        Data([0xff, 0xee, 0xdd, 0xcc, 0xbb, 0xaa, 0x99, 0x88, 0x77, 0x66, 0x55, 0x44, 0x33, 0x22, 0x11, 0x00, 0x99, 0x88])
    }

    // MARK: - Wire-format helpers

    private static func encodeVarint(_ value: UInt64) -> Data {
        var v = value
        var data = Data()
        while v > 0x7f {
            data.append(UInt8(v & 0x7f) | 0x80)
            v >>= 7
        }
        data.append(UInt8(v & 0x7f))
        return data
    }

    private static func encodeFieldHeader(fieldNumber: Int, wireType: Int) -> Data {
        encodeVarint(UInt64(fieldNumber << 3 | wireType))
    }

    private static func encodeLengthDelimited(_ payload: Data) -> Data {
        var result = encodeVarint(UInt64(payload.count))
        result.append(payload)
        return result
    }

    // MARK: - Gzip wrapping
    //
    // Wrap deflate-compressed bytes in a minimal gzip envelope:
    //   header: 0x1f 0x8b 0x08 0x00 (4 bytes magic + method + flags)
    //   mtime: 4 bytes (zeroed)
    //   xfl: 1 byte (zero)
    //   os: 1 byte (0xff = unknown)
    //   ...deflate payload...
    //   crc32: 4 bytes
    //   isize: 4 bytes (uncompressed size mod 2^32)

    private static func gzipCompress(_ data: Data) -> Data {
        var out = Data()
        out.append(contentsOf: [0x1f, 0x8b, 0x08, 0x00])  // magic + method + flags
        out.append(contentsOf: [0x00, 0x00, 0x00, 0x00])  // mtime
        out.append(contentsOf: [0x00, 0xff])              // xfl + os

        let deflated = deflateCompress(data)
        out.append(deflated)

        let crc = crc32(data)
        out.append(contentsOf: [
            UInt8(crc & 0xff),
            UInt8((crc >> 8) & 0xff),
            UInt8((crc >> 16) & 0xff),
            UInt8((crc >> 24) & 0xff),
        ])
        let size = UInt32(data.count & 0xffff_ffff)
        out.append(contentsOf: [
            UInt8(size & 0xff),
            UInt8((size >> 8) & 0xff),
            UInt8((size >> 16) & 0xff),
            UInt8((size >> 24) & 0xff),
        ])
        return out
    }

    private static func deflateCompress(_ data: Data) -> Data {
        let capacity = data.count * 2 + 64
        let dest = UnsafeMutablePointer<UInt8>.allocate(capacity: capacity)
        defer { dest.deallocate() }
        let count = data.withUnsafeBytes { (src: UnsafeRawBufferPointer) -> Int in
            guard let base = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return compression_encode_buffer(
                dest, capacity, base, data.count, nil, COMPRESSION_ZLIB
            )
        }
        return Data(bytes: dest, count: count)
    }

    /// CRC-32/IEEE — small implementation; only used to build valid gzip
    /// trailers in tests, never on the read path.
    private static func crc32(_ data: Data) -> UInt32 {
        var table = [UInt32](repeating: 0, count: 256)
        for n in 0..<256 {
            var c = UInt32(n)
            for _ in 0..<8 {
                c = (c & 1 != 0) ? (0xedb8_8320 ^ (c >> 1)) : (c >> 1)
            }
            table[n] = c
        }
        var crc: UInt32 = 0xffff_ffff
        for byte in data {
            crc = table[Int((crc ^ UInt32(byte)) & 0xff)] ^ (crc >> 8)
        }
        return crc ^ 0xffff_ffff
    }
}
