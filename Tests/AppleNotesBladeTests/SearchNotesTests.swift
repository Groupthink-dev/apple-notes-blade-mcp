import XCTest
@testable import AppleNotesBlade

final class SearchNotesTests: XCTestCase {

    var storePath: String!
    var store: NoteStore!

    override func setUp() async throws {
        let (config, path) = try SampleNoteStoreBuilder.makeSampleConfig()
        self.storePath = path
        self.store = try NoteStore(config: config)
    }

    override func tearDown() async throws {
        if let storePath = storePath {
            SampleNoteStoreBuilder.cleanup(path: storePath)
        }
        store = nil
        storePath = nil
    }

    func testFindsByTitleSubstring() async throws {
        let results = try await store.searchNotes(query: "Recipe")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Recipe — pesto")
    }

    func testFindsBySnippetSubstring() async throws {
        let results = try await store.searchNotes(query: "pine nuts")
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results.first?.title, "Recipe — pesto")
    }

    func testFolderFilter() async throws {
        let results = try await store.searchNotes(query: "Hello", folderID: 11)
        XCTAssertEqual(results.count, 0)

        let inFolder10 = try await store.searchNotes(query: "Hello", folderID: 10)
        XCTAssertEqual(inFolder10.count, 1)
    }

    func testEmptyMatchReturnsEmpty() async throws {
        let results = try await store.searchNotes(query: "ZZZNOTHINGMATCHES")
        XCTAssertEqual(results.count, 0)
    }

    func testHonoursLimit() async throws {
        let results = try await store.searchNotes(query: "list", limit: 1)
        XCTAssertLessThanOrEqual(results.count, 1)
    }

    func testHonoursSinceFilter() async throws {
        // modDate1 = 770_000_000 (Hello world only); cutoff above that excludes it.
        let cutoff = Date(timeIntervalSinceReferenceDate: 770_050_000)
        let results = try await store.searchNotes(query: "world", since: cutoff)
        XCTAssertEqual(results.count, 0)
    }
}
