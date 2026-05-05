import Foundation
import MCP

/// Handler for `apple_notes_search_notes`. v0.1.0 implementation: SQL `LIKE`
/// against `ZTITLE1` and `ZSNIPPET` — never opens body bytes. Real FTS via
/// Apple's `NoteStoreFTS.sqlite` companion file is deferred.
public struct SearchNotesHandler: Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func handle(arguments: [String: Value]?) async -> CallTool.Result {
        guard case .string(let query) = arguments?["query"], !query.isEmpty else {
            return errorResult(.internalError("missing or empty query"))
        }
        let accountID: Int64? = {
            if case .int(let i) = arguments?["account_id"] { return Int64(i) }
            return nil
        }()
        let folderID: Int64? = {
            if case .int(let i) = arguments?["folder_id"] { return Int64(i) }
            return nil
        }()
        let since: Date? = {
            if case .string(let raw) = arguments?["since"] { return parseISO8601(raw) }
            return nil
        }()
        let limit: Int = {
            if case .int(let i) = arguments?["limit"] { return i }
            return 50
        }()

        do {
            let results = try await store.searchNotes(
                query: query,
                accountID: accountID,
                folderID: folderID,
                since: since,
                limit: limit
            )
            return makeResult(payload: SearchNotesResponse(query: query, results: results))
        } catch let error as NotesBladeError {
            return errorResult(error)
        } catch {
            return errorResult(.internalError(String(describing: error)))
        }
    }

    private struct SearchNotesResponse: Codable {
        let query: String
        let results: [NoteSummary]
    }
}
