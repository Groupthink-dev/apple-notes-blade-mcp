import Foundation
import MCP

/// Handler for `apple_notes_list_notes`. Index-only — never decodes bodies.
public struct ListNotesHandler: Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func handle(arguments: [String: Value]?) async -> CallTool.Result {
        guard case .int(let folderRaw) = arguments?["folder_id"] else {
            return errorResult(.internalError("missing or non-integer folder_id"))
        }
        let folderID = Int64(folderRaw)

        let since: Date? = {
            guard case .string(let raw) = arguments?["since"] else { return nil }
            return parseISO8601(raw)
        }()
        let limit: Int = {
            if case .int(let i) = arguments?["limit"] { return i }
            return 100
        }()
        let offset: Int = {
            if case .int(let i) = arguments?["offset"] { return i }
            return 0
        }()

        do {
            let notes = try await store.listNotes(
                folderID: folderID, since: since, limit: limit, offset: offset
            )
            let payload = ListNotesResponse(notes: notes)
            return makeResult(payload: payload)
        } catch let error as NotesBladeError {
            return errorResult(error)
        } catch {
            return errorResult(.internalError(String(describing: error)))
        }
    }

    private struct ListNotesResponse: Codable {
        let notes: [NoteSummary]
    }
}

/// ISO-8601 parser that accepts both with-fractional-seconds and bare forms.
/// Constructed per-call rather than module-global to satisfy Swift 6 strict
/// concurrency (`ISO8601DateFormatter` is not `Sendable`).
func parseISO8601(_ raw: String) -> Date? {
    let withFraction = ISO8601DateFormatter()
    withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    if let d = withFraction.date(from: raw) { return d }
    let bare = ISO8601DateFormatter()
    bare.formatOptions = [.withInternetDateTime]
    return bare.date(from: raw)
}
