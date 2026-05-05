import Foundation
import MCP

/// Handler for `apple_notes_head`. Cheap metadata lookup — never inflates
/// ZDATA. Useful for triage skills that want to decide whether a note's
/// body is worth fetching.
public struct HeadHandler: Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func handle(arguments: [String: Value]?) async -> CallTool.Result {
        guard case .int(let idRaw) = arguments?["id"] else {
            return errorResult(.internalError("missing or non-integer id"))
        }
        let noteID = Int64(idRaw)

        do {
            let head = try await store.head(id: noteID)
            return makeResult(payload: head)
        } catch let error as NotesBladeError {
            return errorResult(error)
        } catch {
            return errorResult(.internalError(String(describing: error)))
        }
    }
}
