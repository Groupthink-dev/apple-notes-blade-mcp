import Foundation
import MCP

/// JSON encoder used by all tool handlers. ISO-8601 dates with fractional
/// seconds; pretty-print disabled (consumer-facing JSON, not human-edit).
/// Constructed per-call to avoid Swift 6 strict-concurrency complaints about
/// `JSONEncoder` instances at module scope.
private func makeToolEncoder() -> JSONEncoder {
    let e = JSONEncoder()
    e.dateEncodingStrategy = .iso8601
    e.keyEncodingStrategy = .useDefaultKeys
    return e
}

/// Wrap any `Codable` payload as a `CallTool.Result` with a single `.text`
/// content item containing the JSON-encoded payload. On encoding failure
/// returns an internal-error result.
func makeResult<T: Codable>(payload: T) -> CallTool.Result {
    do {
        let data = try makeToolEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)])
    } catch {
        return CallTool.Result(
            content: [.text(text: #"{"error":"encode_failure"}"#, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

/// Wrap any `Codable` payload + a DD-338 `_meta:` envelope as a `CallTool.Result`.
/// The envelope is appended to the JSON payload via the canonical `\n\n` separator
/// per `appendMeta`. On encode failure falls through to `errorResult(.internalError(...))`
/// (no envelope on errors per Wave 3 OQ-7 ratification).
///
/// Use at every Track-promoted handler site to avoid per-handler boilerplate around
/// encode + envelope-append. See `MetaEnvelope.swift` for the helper module.
func makeResultWithMeta<T: Codable>(payload: T, meta: MetaEnvelope) -> CallTool.Result {
    do {
        let data = try makeToolEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? "{}"
        let text = appendMeta(json, formatMetaLine(meta))
        return CallTool.Result(content: [.text(text: text, annotations: nil, _meta: nil)])
    } catch {
        return errorResult(.internalError("encode_failure"))
    }
}

/// Wrap a `NotesBladeError` as an error result. The `error` shape is stable;
/// consumer-side skills can switch on `error.code`.
func errorResult(_ error: NotesBladeError) -> CallTool.Result {
    let payload = ErrorPayload(error: ErrorBody(from: error))
    do {
        let data = try makeToolEncoder().encode(payload)
        let json = String(data: data, encoding: .utf8) ?? #"{"error":{"code":"unknown"}}"#
        return CallTool.Result(content: [.text(text: json, annotations: nil, _meta: nil)], isError: true)
    } catch {
        return CallTool.Result(
            content: [.text(text: #"{"error":{"code":"encode_failure"}}"#, annotations: nil, _meta: nil)],
            isError: true
        )
    }
}

private struct ErrorPayload: Codable {
    let error: ErrorBody
}

private struct ErrorBody: Codable {
    let code: String
    let message: String
    let path: String?
    let recovery: String?
    let noteID: Int64?

    init(from error: NotesBladeError) {
        switch error {
        case .permissionDenied(let path):
            self.code = "permission_denied"
            self.message = "Full Disk Access required to read \(path)."
            self.path = path
            self.recovery = NotesBladeError.pointerToFullDiskAccess
            self.noteID = nil
        case .storeMissing(let path):
            self.code = "store_missing"
            self.message = "NoteStore.sqlite not found at \(path)."
            self.path = path
            self.recovery = nil
            self.noteID = nil
        case .storeLocked:
            self.code = "store_locked"
            self.message = "NoteStore.sqlite is busy; retry later."
            self.path = nil
            self.recovery = nil
            self.noteID = nil
        case .invalidStorePath(let path):
            self.code = "invalid_store_path"
            self.message = "Store path \(path) is outside the allowed prefixes."
            self.path = path
            self.recovery = nil
            self.noteID = nil
        case .decodeFailure(let id, let reason):
            self.code = "decode_failure"
            self.message = "Failed to decode note: \(reason)"
            self.path = nil
            self.recovery = nil
            self.noteID = id
        case .sqliteError(let code, let msg):
            self.code = "sqlite_error"
            self.message = "SQLite error code=\(code): \(msg)"
            self.path = nil
            self.recovery = nil
            self.noteID = nil
        case .internalError(let label):
            self.code = "internal_error"
            self.message = label
            self.path = nil
            self.recovery = nil
            self.noteID = nil
        }
    }
}
