import Foundation
import MCP

/// Handler for `apple_notes_list_folders`. Optional `account_id` filter.
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

        do {
            let folders = try await store.listFolders(accountID: accountID)
            let payload = ListFoldersResponse(folders: folders)
            return makeResult(payload: payload)
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
