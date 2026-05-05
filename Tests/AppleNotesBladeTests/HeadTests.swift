import XCTest
@testable import AppleNotesBlade

final class HeadTests: XCTestCase {

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

    func testHeadReturnsMetadataWithoutBody() async throws {
        let head = try await store.head(id: 100)
        XCTAssertEqual(head.id, 100)
        XCTAssertEqual(head.title, "Hello world")
        XCTAssertEqual(head.folderID, 10)
        XCTAssertNotNil(head.bodyByteLength)
        XCTAssertGreaterThan(head.bodyByteLength ?? 0, 0)
    }

    func testHeadReportsAttachmentCount() async throws {
        let head = try await store.head(id: 102)
        XCTAssertEqual(head.attachmentCount, 1)
        XCTAssertTrue(head.hasAttachments)
    }

    func testHeadReportsPinned() async throws {
        let head = try await store.head(id: 101)
        XCTAssertEqual(head.title, "Recipe — pesto")
    }

    func testHeadUnknownIDThrows() async {
        do {
            _ = try await store.head(id: 999_999)
            XCTFail("expected internalError")
        } catch let error as NotesBladeError {
            guard case .internalError = error else {
                return XCTFail("expected internalError, got \(error)")
            }
        } catch {
            XCTFail("unexpected: \(error)")
        }
    }
}
