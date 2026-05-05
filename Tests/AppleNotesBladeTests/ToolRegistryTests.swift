import XCTest
import MCP
@testable import AppleNotesBlade

final class ToolRegistryTests: XCTestCase {

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

    func testRegistryExposesFiveTools() {
        let names = Set(registry.tools().map { $0.name })
        XCTAssertEqual(
            names,
            Set([
                "apple_notes_list_folders",
                "apple_notes_list_notes",
                "apple_notes_read_note",
                "apple_notes_search_notes",
                "apple_notes_head",
            ])
        )
    }

    func testHandleListFoldersDispatches() async throws {
        let result = await registry.handleCall(name: "apple_notes_list_folders", arguments: nil)
        XCTAssertFalse(result.isError ?? false)
        XCTAssertFalse(result.content.isEmpty)
    }

    func testHandleListNotesRequiresFolderID() async throws {
        // Missing folder_id — handler returns isError: true with internal_error.
        let result = await registry.handleCall(name: "apple_notes_list_notes", arguments: nil)
        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleListNotesWithFolderIDSucceeds() async throws {
        let args: [String: Value] = ["folder_id": .int(10)]
        let result = await registry.handleCall(name: "apple_notes_list_notes", arguments: args)
        XCTAssertFalse(result.isError ?? false)
    }

    func testHandleReadNoteRoundTrips() async throws {
        let args: [String: Value] = ["id": .int(100)]
        let result = await registry.handleCall(name: "apple_notes_read_note", arguments: args)
        XCTAssertFalse(result.isError ?? false)
        // Inspect the JSON content to confirm body round-trip.
        guard case .text(let json, _, _) = result.content.first else {
            return XCTFail("expected text content")
        }
        XCTAssertTrue(json.contains("Hello world body"), "body string missing from result: \(json)")
    }

    func testHandleSearchNotesRequiresQuery() async throws {
        let result = await registry.handleCall(name: "apple_notes_search_notes", arguments: nil)
        XCTAssertTrue(result.isError ?? false)
    }

    func testHandleHeadDispatches() async throws {
        let args: [String: Value] = ["id": .int(100)]
        let result = await registry.handleCall(name: "apple_notes_head", arguments: args)
        XCTAssertFalse(result.isError ?? false)
    }

    func testHandleUnknownToolReturnsError() async throws {
        let result = await registry.handleCall(name: "apple_notes_nope", arguments: nil)
        XCTAssertTrue(result.isError ?? false)
    }

    func testToolSchemasAreWellFormed() {
        for tool in registry.tools() {
            XCTAssertFalse(tool.name.isEmpty)
            XCTAssertFalse(tool.description?.isEmpty ?? true)
            // Each tool's input schema must be a JSON-schema object.
            // Tool.inputSchema is non-optional Value here; assert its shape.
            guard case .object = tool.inputSchema else {
                return XCTFail("tool \(tool.name) has non-object input schema")
            }
        }
    }
}
