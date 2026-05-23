import Foundation
import MCP

/// Handler for `apple_notes_list_folders`. Optional `account_id` filter.
///
/// DD-338 Phase C Wave 5: emits canonical `_meta:` envelope (B-tier promotion).
public struct ListFoldersHandler: Sendable {
    public let store: NoteStore

    public init(store: NoteStore) {
        self.store = store
    }

    public func handle(arguments: [String: Value]?) async -> CallTool.Result {
        let accountID: Int64? = {
            guard case .int(let i) = arguments?["account_id"] else { return nil }
            return Int64(i)
        }()

        let t0 = ContinuousClock.now
        do {
            let folders = try await store.listFolders(accountID: accountID)
            let elapsed = ContinuousClock.now - t0
            var filteredBy: [String] = []
            if let accountID {
                filteredBy.append("account_id=\(accountID)")
            }
            filteredBy.sort()
            let meta = MetaEnvelope(
                matchedTotal: folders.count,
                returned: folders.count,
                filteredBy: filteredBy,
                latencyMs: elapsed.toMilliseconds()
            )
            return makeResultWithMeta(
                payload: ListFoldersResponse(folders: folders),
                meta: meta
            )
        } catch let error as NotesBladeError {
            return errorResult(error)
        } catch {
            return errorResult(.internalError(String(describing: error)))
        }
    }

    private struct ListFoldersResponse: Codable {
        let folders: [Folder]
    }
}
