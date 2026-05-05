import XCTest
@testable import AppleNotesBlade

final class ConfigTests: XCTestCase {

    func testDefaultPathValidates() throws {
        let config = try NotesBladeConfig()
        XCTAssertTrue(config.storePath.contains("Group Containers/group.com.apple.notes"))
    }

    func testTmpPathIsAccepted() throws {
        let path = "/private/tmp/test-\(UUID().uuidString)/NoteStore.sqlite"
        let config = try NotesBladeConfig(storePath: path)
        XCTAssertEqual(config.storePath, path)
    }

    func testArbitraryPathIsRejected() {
        XCTAssertThrowsError(try NotesBladeConfig(storePath: "/etc/passwd")) { error in
            guard case NotesBladeError.invalidStorePath(let path) = error else {
                return XCTFail("expected invalidStorePath, got \(error)")
            }
            XCTAssertEqual(path, "/etc/passwd")
        }
    }

    func testTraversalPathIsRejected() {
        // Attempt to escape the canonical prefix via `..` segment.
        let path = "/private/tmp/foo/../../../../etc/passwd"
        XCTAssertThrowsError(try NotesBladeConfig(storePath: path)) { error in
            guard case NotesBladeError.invalidStorePath = error else {
                return XCTFail("expected invalidStorePath, got \(error)")
            }
        }
    }

    func testHardCapClampsToAtLeastOne() throws {
        let config = try NotesBladeConfig(maxResultsHardCap: 0)
        XCTAssertEqual(config.maxResultsHardCap, 1)
    }
}
