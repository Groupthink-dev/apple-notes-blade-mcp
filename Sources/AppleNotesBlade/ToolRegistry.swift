import Foundation
import MCP

/// Public registry façade. Mirrors the shape used by `stallari-vault`'s
/// `ToolRegistry`: `tools()` returns the MCP tool definitions; `handleCall`
/// dispatches a CallTool by name to the appropriate handler.
///
/// This is the **only** public type the consuming wiring code in StallariKit
/// needs to interact with. Construction takes a validated `NotesBladeConfig`;
/// the registry opens the underlying `NoteStore` and holds it for the lifetime
/// of the daemon.
///
/// **Internal-only consumption.** This registry is registered with
/// StallariKit's internal tool catalog only. The 5 Notes tools are never
/// advertised on the daemon's public `:9847/mcp` HTTP MCP surface. See
/// `directives/local-corpus-blades.md` for the class invariants.
public actor AppleNotesToolRegistry {

    public let store: NoteStore
    private let listFolders: ListFoldersHandler
    private let listNotes: ListNotesHandler

    public init(config: NotesBladeConfig) throws {
        self.store = try NoteStore(config: config)
        self.listFolders = ListFoldersHandler(store: store)
        self.listNotes = ListNotesHandler(store: store)
    }

    /// Convenience constructor using the default canonical Apple Notes path.
    /// Throws `NotesBladeError.invalidStorePath` only in the unlikely event
    /// that `NSHomeDirectory()` returns something the path validator rejects.
    public init() throws {
        try self.init(config: try NotesBladeConfig())
    }

    /// All tool definitions, suitable for ListTools response.
    public nonisolated func tools() -> [Tool] {
        NotesToolSchemas.all()
    }

    /// Dispatch a CallTool. Unknown names return an internal-error result
    /// rather than throwing — mirrors `stallari-vault`'s ToolRegistry.
    public func handleCall(name: String, arguments: [String: Value]?) async -> CallTool.Result {
        switch name {
        case "apple_notes_list_folders":
            return await listFolders.handle(arguments: arguments)
        case "apple_notes_list_notes":
            return await listNotes.handle(arguments: arguments)
        default:
            return errorResult(.internalError("unknown tool: \(name)"))
        }
    }

}
