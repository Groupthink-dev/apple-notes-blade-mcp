import XCTest
@testable import AppleNotesBlade

final class ProtobufDecoderTests: XCTestCase {

    func testDecodesSimpleNoteBody() throws {
        let zdata = ProtobufFixtures.makeNoteBody("Hello, this is a note about kitchen renovation.")
        let decoded = try ProtobufNotesDecoder(noteID: 100).decode(zdata: zdata)
        XCTAssertEqual(decoded.plainText, "Hello, this is a note about kitchen renovation.")
        XCTAssertTrue(decoded.attachments.isEmpty)
    }

    func testDecodesUTF8MultibyteBody() throws {
        let body = "Café — résumé · 漢字 · 🌳"
        let zdata = ProtobufFixtures.makeNoteBody(body)
        let decoded = try ProtobufNotesDecoder(noteID: 101).decode(zdata: zdata)
        XCTAssertEqual(decoded.plainText, body)
    }

    func testExtractsAttachmentIdentifier() throws {
        let uuid = "F4DCEC4A-1234-5678-90AB-CDEF12345678"
        let body = "Photo of the new oven, see attached."
        let zdata = ProtobufFixtures.makeNoteBody(body, attachmentUUID: uuid)
        let decoded = try ProtobufNotesDecoder(noteID: 102).decode(zdata: zdata)
        XCTAssertEqual(decoded.plainText, body)
        XCTAssertEqual(decoded.attachments.count, 1)
        XCTAssertEqual(decoded.attachments.first?.identifier, uuid)
    }

    // MARK: - Hardening

    func testRejectsEmptyBlob() {
        XCTAssertThrowsError(try ProtobufNotesDecoder(noteID: 200).decode(zdata: Data())) { error in
            guard case NotesBladeError.decodeFailure = error else {
                return XCTFail("expected decodeFailure, got \(error)")
            }
        }
    }

    func testRejectsNonGzipBlob() {
        let bad = ProtobufFixtures.makeNonGzipBlob()
        XCTAssertThrowsError(try ProtobufNotesDecoder(noteID: 201).decode(zdata: bad)) { error in
            guard case NotesBladeError.decodeFailure(_, let reason) = error else {
                return XCTFail("expected decodeFailure")
            }
            XCTAssertTrue(reason.contains("gzip"), "Expected gzip-shaped error reason, got: \(reason)")
        }
    }

    func testHandlesModeratelyDeepNesting() throws {
        // Below the maxDepth budget — should succeed.
        let body = "A note nested twenty layers deep."
        let zdata = ProtobufFixtures.makeDeeplyNestedBody(body, depth: 20)
        let decoded = try ProtobufNotesDecoder(noteID: 300).decode(zdata: zdata)
        XCTAssertEqual(decoded.plainText, body)
    }

    func testHandlesExcessivelyDeepNestingGracefully() throws {
        // Beyond the maxDepth budget. The walker stops descending past the
        // budget *and* swallows the depth-exceeded error from inside
        // `processLengthDelimited` (so a single deep branch doesn't poison
        // an otherwise-valid message). Result: decode "succeeds" but the
        // body string never surfaces. The assertion is degrade-gracefully:
        // we get an empty body, not a crash and not a leaking exception.
        let zdata = ProtobufFixtures.makeDeeplyNestedBody("body", depth: ProtobufNotesDecoder.maxDepth + 5)
        let decoded = try ProtobufNotesDecoder(noteID: 301).decode(zdata: zdata)
        XCTAssertEqual(decoded.plainText, "")
    }

    // MARK: - Heuristic guards

    func testReadableTextHeuristicAcceptsPlainText() {
        XCTAssertTrue(ProtobufNotesDecoder.looksLikeReadableText("hello world"))
        XCTAssertTrue(ProtobufNotesDecoder.looksLikeReadableText("Multi\nline\nnote"))
        XCTAssertTrue(ProtobufNotesDecoder.looksLikeReadableText("Tab\there"))
    }

    func testReadableTextHeuristicRejectsControlByteSoup() {
        // Bunch of control bytes (< 0x20) — should be rejected.
        let bytes = Data([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09])
        if let s = String(data: bytes, encoding: .utf8) {
            XCTAssertFalse(ProtobufNotesDecoder.looksLikeReadableText(s))
        }
    }

    func testReadableTextHeuristicRejectsEmbeddedNUL() {
        let s = "hello\0world"
        XCTAssertFalse(ProtobufNotesDecoder.looksLikeReadableText(s))
    }

    func testAttachmentIdentifierShape() {
        XCTAssertTrue(ProtobufNotesDecoder.looksLikeAttachmentIdentifier(
            "F4DCEC4A-1234-5678-90AB-CDEF12345678"
        ))
        XCTAssertFalse(ProtobufNotesDecoder.looksLikeAttachmentIdentifier("not-a-uuid"))
        XCTAssertFalse(ProtobufNotesDecoder.looksLikeAttachmentIdentifier(
            "ZZZZZZZZ-1234-5678-90AB-CDEF12345678"  // non-hex
        ))
    }
}
