import Foundation
import MCP

/// Handler for `apple_notes_search_notes`. v0.1.0 implementation: SQL `LIKE`
/// against `ZTITLE1` and `ZSNIPPET` — never opens body bytes. Real FTS via
/// Apple's `NoteStoreFTS.sqlite` companion file is deferred.
///
/// DD-338 Phase C Wave 5: emits canonical `_meta:` envelope (B-tier promotion).
/// `filtered_by` `query=` is SHA-256-12 hashed per privacy discipline (mirrors
/// apple-mail search + W3 OQ-6 for `cf_d1_query`).
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
        let sinceRaw: String? = {
            if case .string(let raw) = arguments?["since"] { return raw }
            return nil
        }()
        let since: Date? = sinceRaw.flatMap { parseISO8601($0) }
        let limitArg: Int? = {
            if case .int(let i) = arguments?["limit"] { return i }
            return nil
        }()
        let limit = limitArg ?? 50

        let t0 = ContinuousClock.now
        do {
            let results = try await store.searchNotes(
                query: query,
                accountID: accountID,
                folderID: folderID,
                since: since,
                limit: limit
            )
            let elapsed = ContinuousClock.now - t0
            var filteredBy: [String] = ["query=\(metaQueryDigest(query))"]
            if let accountID {
                filteredBy.append("account_id=\(accountID)")
            }
            if let folderID {
                filteredBy.append("folder_id=\(folderID)")
            }
            if let sinceRaw {
                filteredBy.append("since=\(sinceRaw)")
            }
            if let limitArg {
                filteredBy.append("limit=\(limitArg)")
            }
            filteredBy.sort()
            let meta = MetaEnvelope(
                matchedTotal: results.count,
                returned: results.count,
                filteredBy: filteredBy,
                latencyMs: elapsed.toMilliseconds()
            )
            return makeResultWithMeta(
                payload: SearchNotesResponse(query: query, results: results),
                meta: meta
            )
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
