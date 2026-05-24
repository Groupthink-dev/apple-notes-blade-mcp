// MetaEnvelopeTests.swift
//
// DD-338 Phase C Wave 5 — envelope-shape + determinism tests for the 3
// audit_surface-promoted apple-notes tools (3 B):
//   - apple_notes_list_folders
//   - apple_notes_list_notes
//   - apple_notes_search_notes
//
// Post-DD-338-Phase-C-Wave-5 cutover: envelope construction + formatting now
// flow through the canonical `MCPHelpers` SPM dep
// (https://github.com/Groupthink-dev/stallari-mcp-helpers-swift). Canonical
// wire-shape vs. the hand-rolled v1 differs in two ways exercised by these
// tests:
//   - `redactions` ALWAYS emitted (defaults to `[]`); was omitted when empty
//   - `next_cursor` ALWAYS emitted (JSON `null` when nil); was omitted when nil
//   - `filtered_by` alphabetically sorted by the formatter (caller no longer
//     needs to pre-sort; existing pre-sort calls remain harmless)
//   - `formatMetaLine` now throws (encoding-failure surface; unreachable in
//     practice for our value types)

import MCP
import MCPHelpers
import XCTest

@testable import AppleNotesBlade

final class MetaEnvelopeTests: XCTestCase {

    var storePath: String!
    var registry: AppleNotesToolRegistry!

    override func setUp() async throws {
        let (config, path) = try SampleNoteStoreBuilder.makeSampleConfig()
        self.storePath = path
        self.registry = try AppleNotesToolRegistry(config: config)
    }

    override func tearDown() async throws {
        if let storePath = storePath {
            SampleNoteStoreBuilder.cleanup(path: storePath)
        }
        registry = nil
        storePath = nil
    }

    // MARK: - Helper / cross-cutting

    private func call(_ name: String, _ args: [String: Value]? = nil) async -> String {
        let result = await registry.handleCall(name: name, arguments: args)
        return extractText(from: result)
    }

    func testMetaEnvelopeFormatterByteShape() throws {
        // Canonical MCPHelpers shape: ALWAYS emits matched_total, returned,
        // filtered_by, latency_ms, redactions, next_cursor (6 required keys).
        // error_notes omitted when nil/empty. `filtered_by` sorted alphabetically.
        let meta = MetaEnvelope(
            matchedTotal: 42,
            returned: 10,
            latencyMs: 87,
            filteredBy: ["folder_id=23", "limit=10"]
        )
        let line = try formatMetaLine(meta)
        XCTAssertTrue(line.hasPrefix("_meta: "))
        let json = String(line.dropFirst("_meta: ".count))
        let data = json.data(using: .utf8)!
        let parsed = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.count, 6)
        XCTAssertEqual(parsed?["matched_total"] as? Int, 42)
        XCTAssertEqual(parsed?["returned"] as? Int, 10)
        // Canonical sorts filtered_by alphabetically.
        XCTAssertEqual(parsed?["filtered_by"] as? [String], ["folder_id=23", "limit=10"])
        XCTAssertEqual(parsed?["latency_ms"] as? Int, 87)
        XCTAssertEqual(parsed?["redactions"] as? [String], [])
        XCTAssertTrue(parsed?["next_cursor"] is NSNull)
    }

    func testMetaEnvelopeAlwaysEmitsRedactionsAndNextCursor() throws {
        // Canonical contract: redactions + next_cursor are REQUIRED fields.
        // Empty redactions → `[]`; nil next_cursor → JSON `null`. error_notes
        // alone is the omit-when-empty optional.
        let meta = MetaEnvelope(
            matchedTotal: 1,
            returned: 1,
            latencyMs: 0,
            filteredBy: [],
            redactions: [],
            nextCursor: nil,
            errorNotes: []
        )
        let line = try formatMetaLine(meta)
        XCTAssertTrue(line.contains("\"redactions\":[]"))
        XCTAssertTrue(line.contains("\"next_cursor\":null"))
        XCTAssertFalse(line.contains("error_notes"))
    }

    func testMetaEnvelopeFilteredBySortedByFormatter() throws {
        // Canonical formatter sorts filteredBy alphabetically — caller order
        // is no longer load-bearing. Tools may still pre-sort for clarity;
        // outcome is identical.
        let meta = MetaEnvelope(
            matchedTotal: 0,
            returned: 0,
            latencyMs: 0,
            filteredBy: ["z=1", "a=2", "m=3"]
        )
        let line = try formatMetaLine(meta)
        XCTAssertTrue(line.contains("\"filtered_by\":[\"a=2\",\"m=3\",\"z=1\"]"))
    }

    func testMetaQueryDigestIsDeterministic() {
        let a = metaQueryDigest("hello world")
        let b = metaQueryDigest("hello world")
        XCTAssertEqual(a, b)
        XCTAssertEqual(a.count, 12)
    }

    // MARK: - apple_notes_list_folders (B)

    func testListFoldersEnvelopePresent() async {
        let text = await call("apple_notes_list_folders")
        let meta = parseMeta(from: text)
        XCTAssertMetaShape(meta)
    }

    func testListFoldersEmptyFilteredByWhenNoArgs() async {
        let text = await call("apple_notes_list_folders")
        let meta = parseMeta(from: text)
        XCTAssertEqual(meta?["filtered_by"] as? [String], [])
    }

    func testListFoldersFilteredByIncludesAccountIDWhenSupplied() async {
        let text = await call("apple_notes_list_folders", ["account_id": .int(1)])
        let meta = parseMeta(from: text)
        XCTAssertEqual(meta?["filtered_by"] as? [String], ["account_id=1"])
    }

    func testListFoldersMatchedEqualsReturned() async {
        let text = await call("apple_notes_list_folders")
        let meta = parseMeta(from: text)
        XCTAssertEqual(meta?["matched_total"] as? Int, meta?["returned"] as? Int)
    }

    func testListFoldersStructuralDeterminismN3() async {
        var seen: [NSDictionary] = []
        for _ in 0..<3 {
            let text = await call("apple_notes_list_folders")
            let payload = payloadJSON(from: text)
            guard let data = payload.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
            else {
                XCTFail("could not parse payload JSON: \(payload)")
                return
            }
            seen.append(obj as NSDictionary)
        }
        let first = seen[0]
        for (i, other) in seen.enumerated().dropFirst() {
            XCTAssertEqual(first, other, "call \(i) diverged from call 0")
        }
    }

    // MARK: - apple_notes_list_notes (B)

    func testListNotesEnvelopePresent() async {
        let text = await call("apple_notes_list_notes", ["folder_id": .int(10)])
        let meta = parseMeta(from: text)
        XCTAssertMetaShape(meta)
    }

    func testListNotesFilteredByContainsFolderID() async {
        let text = await call("apple_notes_list_notes", ["folder_id": .int(10)])
        let meta = parseMeta(from: text)
        let fb = meta?["filtered_by"] as? [String] ?? []
        XCTAssertTrue(fb.contains("folder_id=10"))
    }

    func testListNotesFilteredBySortedAlphabetically() async {
        let text = await call("apple_notes_list_notes", [
            "folder_id": .int(10),
            "limit": .int(5),
            "offset": .int(0),
        ])
        let meta = parseMeta(from: text)
        let fb = meta?["filtered_by"] as? [String] ?? []
        XCTAssertEqual(fb, fb.sorted())
        XCTAssertTrue(fb.contains("limit=5"))
        XCTAssertTrue(fb.contains("offset=0"))
        XCTAssertTrue(fb.contains("folder_id=10"))
    }

    func testListNotesMatchedEqualsReturned() async {
        let text = await call("apple_notes_list_notes", ["folder_id": .int(10)])
        let meta = parseMeta(from: text)
        XCTAssertEqual(meta?["matched_total"] as? Int, meta?["returned"] as? Int)
    }

    func testListNotesNextCursorAlwaysPresentAsNull() async {
        // Per canonical MCPHelpers contract: next_cursor is REQUIRED; offset-
        // paginated tools emit JSON `null`. Was omit-when-nil in hand-rolled v1
        // (DD-338 W5 OQ-6) — canonical promotes to always-present.
        let text = await call("apple_notes_list_notes", ["folder_id": .int(10)])
        let meta = parseMeta(from: text)
        XCTAssertNotNil(meta)
        XCTAssertTrue(meta?["next_cursor"] is NSNull)
    }

    // MARK: - apple_notes_search_notes (B)

    func testSearchNotesEnvelopePresent() async {
        let text = await call("apple_notes_search_notes", ["query": .string("hello")])
        let meta = parseMeta(from: text)
        XCTAssertMetaShape(meta)
    }

    func testSearchNotesQueryFieldIsHashedNotRaw() async {
        let text = await call("apple_notes_search_notes", ["query": .string("secret-token-xyz")])
        let meta = parseMeta(from: text)
        let fb = meta?["filtered_by"] as? [String] ?? []
        XCTAssertFalse(fb.contains(where: { $0.contains("secret-token-xyz") }))
        let queryEntries = fb.filter { $0.hasPrefix("query=") }
        XCTAssertEqual(queryEntries.count, 1)
        let digest = String(queryEntries[0].dropFirst("query=".count))
        XCTAssertEqual(digest.count, 12)
    }

    func testSearchNotesQueryDigestIsDeterministic() async {
        let textA = await call("apple_notes_search_notes", ["query": .string("repeated")])
        let textB = await call("apple_notes_search_notes", ["query": .string("repeated")])
        let metaA = parseMeta(from: textA)
        let metaB = parseMeta(from: textB)
        let fbA = (metaA?["filtered_by"] as? [String])?.first(where: { $0.hasPrefix("query=") })
        let fbB = (metaB?["filtered_by"] as? [String])?.first(where: { $0.hasPrefix("query=") })
        XCTAssertNotNil(fbA)
        XCTAssertEqual(fbA, fbB)
    }

    func testSearchNotesFilteredBySortedAlphabetically() async {
        let text = await call("apple_notes_search_notes", [
            "query": .string("hello"),
            "folder_id": .int(10),
            "limit": .int(5),
        ])
        let meta = parseMeta(from: text)
        let fb = meta?["filtered_by"] as? [String] ?? []
        XCTAssertEqual(fb, fb.sorted())
    }

    func testSearchNotesMatchedEqualsReturned() async {
        let text = await call("apple_notes_search_notes", ["query": .string("hello")])
        let meta = parseMeta(from: text)
        XCTAssertEqual(meta?["matched_total"] as? Int, meta?["returned"] as? Int)
    }

    func testSearchNotesPayloadStableAcrossEnvelopeAddition() async {
        let text = await call("apple_notes_search_notes", ["query": .string("hello")])
        XCTAssertTrue(text.contains("\"query\""))
        XCTAssertTrue(text.contains("\n\n_meta: "))
    }

    // MARK: - canonical-shape gate (DD-338 W5 acceptance criterion)

    func testFormatMetaLineEmitsCanonicalMCPHelpersShape() throws {
        // Gate against future drift between this blade's emission and the
        // canonical MCPHelpers wire shape. The canonical input/output pair
        // mirrors the MCPHelpers Swift v0.1.0 own test fixture: required
        // fields populated, optional errorNotes omitted, filtered_by sorted.
        let meta = MetaEnvelope(
            matchedTotal: 100,
            returned: 25,
            latencyMs: 12,
            filteredBy: ["b=2", "a=1"],
            redactions: [],
            nextCursor: nil,
            errorNotes: nil
        )
        let line = try formatMetaLine(meta)
        XCTAssertEqual(
            line,
            #"_meta: {"matched_total":100,"returned":25,"filtered_by":["a=1","b=2"],"latency_ms":12,"redactions":[],"next_cursor":null}"#
        )
    }
}
