import Foundation

/// Error vocabulary for the Notes blade. Errors **carry IDs only** — never note
/// bodies or titles — to keep error surfaces non-leaking when they bubble up
/// through traces / logs.
public enum NotesBladeError: Error, Sendable, Equatable {
    /// Full Disk Access not granted on the consuming binary. The associated
    /// path is the absolute store path that we attempted to open. Recovery
    /// pointer is `pointerToFullDiskAccess` below.
    case permissionDenied(path: String)

    /// `NoteStore.sqlite` does not exist at the configured path. Likely cause:
    /// macOS path schema change, or the user has never opened Notes.app on
    /// this Mac.
    case storeMissing(path: String)

    /// SQLite returned `SQLITE_BUSY` past the busy-timeout window. The store
    /// is being held exclusively by another writer (Notes.app sync, Spotlight
    /// indexing). Caller should retry with a small backoff or give up.
    case storeLocked

    /// `Config.storePath` was set to a value outside the allowed prefixes
    /// (`/private/tmp/*` and the canonical Apple Notes Group Container path).
    /// Carries the rejected path.
    case invalidStorePath(path: String)

    /// A protobuf decode failed — bounded-recursion guard fired, max-message-size
    /// guard fired, or the byte stream is genuinely malformed. The associated
    /// reason is human-readable; the note ID identifies which note. Body is
    /// never embedded.
    case decodeFailure(noteID: Int64, reason: String)

    /// SQLite layer reported an unexpected condition. Phrased generically to
    /// avoid leaking schema details into traces.
    case sqliteError(code: Int32, message: String)

    /// Catchall for assertion-shaped surprises. Always carries a short label.
    case internalError(String)
}

extension NotesBladeError {
    /// Stable pointer string included in `permissionDenied` errors so the
    /// consuming skill / UI can surface the exact System Settings pane.
    public static let pointerToFullDiskAccess =
        "Open System Settings → Privacy & Security → Full Disk Access and enable Stallari."

    /// Human-readable summary suitable for logging. **Never** includes note
    /// bodies; note IDs are surfaced for debug correlation only.
    public var loggableDescription: String {
        switch self {
        case .permissionDenied(let path):
            return "permissionDenied: cannot read \(path) — \(Self.pointerToFullDiskAccess)"
        case .storeMissing(let path):
            return "storeMissing: \(path) does not exist"
        case .storeLocked:
            return "storeLocked: NoteStore.sqlite is busy; retry later"
        case .invalidStorePath(let path):
            return "invalidStorePath: \(path) is outside the allowed prefixes"
        case .decodeFailure(let id, let reason):
            return "decodeFailure: note id=\(id) reason=\(reason)"
        case .sqliteError(let code, let message):
            return "sqliteError: code=\(code) message=\(message)"
        case .internalError(let label):
            return "internalError: \(label)"
        }
    }
}
