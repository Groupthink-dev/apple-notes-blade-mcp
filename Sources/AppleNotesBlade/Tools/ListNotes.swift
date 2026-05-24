import Foundation
import MCP
import MCPHelpers

/// Handler for `apple_notes_list_notes`. Index-only — never decodes bodies.
///
/// DD-338 Phase C Wave 5: emits canonical `_meta:` envelope (B-tier promotion).
/// `matched_total = returned` per Wave 5 OQ-4 ratification (post-LIMIT at v1).
/// `next_cursor` omitted for offset-paginated tools per OQ-6.
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

        let sinceRaw: String? = {
            guard case .string(let raw) = arguments?["since"] else { return nil }
            return raw
        }()
        let since: Date? = sinceRaw.flatMap { parseISO8601($0) }
        let limitArg: Int? = {
            if case .int(let i) = arguments?["limit"] { return i }
            return nil
        }()
        let offsetArg: Int? = {
            if case .int(let i) = arguments?["offset"] { return i }
            return nil
        }()
        let limit = limitArg ?? 100
        let offset = offsetArg ?? 0

        let t0 = ContinuousClock.now
        do {
            let notes = try await store.listNotes(
                folderID: folderID, since: since, limit: limit, offset: offset
            )
            let elapsed = ContinuousClock.now - t0
            var filteredBy: [String] = ["folder_id=\(folderID)"]
            if let limitArg {
                filteredBy.append("limit=\(limitArg)")
            }
            if let offsetArg {
                filteredBy.append("offset=\(offsetArg)")
            }
            if let sinceRaw {
                filteredBy.append("since=\(sinceRaw)")
            }
            filteredBy.sort()
            let meta = MetaEnvelope(
                matchedTotal: notes.count,
                returned: notes.count,
                latencyMs: elapsed.toMilliseconds(),
                filteredBy: filteredBy
            )
            return makeResultWithMeta(
                payload: ListNotesResponse(notes: notes),
                meta: meta
            )
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
