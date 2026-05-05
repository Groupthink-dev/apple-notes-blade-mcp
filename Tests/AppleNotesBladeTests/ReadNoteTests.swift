import XCTest
@testable import AppleNotesBlade

final class ReadNoteTests: XCTestCase {

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

    func testReadNoteRoundTripsTheCanonicalBody() async throws {
        let note = try await store.readNote(id: 100)
        XCTAssertEqual(note.id, 100)
        XCTAssertEqual(note.folderID, 10)
        XCTAssertEqual(note.title, "Hello world")
        XCTAssertEqual(note.bodyText, SampleNoteStoreBuilder.body100)
        XCTAssertNil(note.bodyHTML)
        XCTAssertFalse(note.htmlNotImplemented)
        XCTAssertTrue(note.attachments.isEmpty)
    }

    func testReadNoteIncludeHTMLSetsSoftSignal() async throws {
        let note = try await store.readNote(id: 100, includeHTML: true)
        XCTAssertTrue(note.htmlNotImplemented)
        XCTAssertNil(note.bodyHTML)
        XCTAssertEqual(note.bodyText, SampleNoteStoreBuilder.body100)
    }

    func testReadNoteSurfacesAttachmentMetadata() async throws {
        let note = try await store.readNote(id: 102)
        XCTAssertEqual(note.bodyText, SampleNoteStoreBuilder.body102)
        XCTAssertEqual(note.attachments.count, 1)
    }

    func testReadNoteUnknownIDThrows() async {
        do {
            _ = try await store.readNote(id: 999_999)
            XCTFail("expected internalError for unknown id")
        } catch let error as NotesBladeError {
            guard case .internalError = error else {
                return XCTFail("expected internalError, got \(error)")
            }
        } catch {
            XCTFail("unexpected error: \(error)")
        }
    }
}
