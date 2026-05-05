import Foundation
import MCP

/// Handler for `apple_notes_read_note`. Inflates and decodes the note's
/// protobuf body. HTML rendering is deferred to a future phase — passing
/// `include_html: true` returns a soft signal in the response (`htmlNotImplemented`)
/// rather than an error.
public struct ReadNoteHandler: Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func handle(arguments: [String: Value]?) async -> CallTool.Result {
        guard case .int(let idRaw) = arguments?["id"] else {
            return errorResult(.internalError("missing or non-integer id"))
        }
        let noteID = Int64(idRaw)

        let includeHTML: Bool = {
            if case .bool(let b) = arguments?["include_html"] { return b }
            return false
        }()

        do {
            let note = try await store.readNote(id: noteID, includeHTML: includeHTML)
            return makeResult(payload: note)
        } catch let error as NotesBladeError {
            return errorResult(error)
        } catch {
            return errorResult(.internalError(String(describing: error)))
        }
    }
}
