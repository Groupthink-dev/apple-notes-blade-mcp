import Foundation

/// Runtime configuration for the Notes blade.
///
/// Path validation is **strict**: `storePath` must point at the canonical
/// Apple Notes Group Container path or under `/private/tmp/` (for fixture
/// tests). Any other prefix is rejected at construction time with
/// `NotesBladeError.invalidStorePath` — this is one of the secops invariants
/// (DD-240 #4 + access-policy section "Local-corpus blade access").
public struct NotesBladeConfig: Sendable {

    /// Absolute path to `NoteStore.sqlite`. Defaults to the canonical Apple
    /// Notes Group Container path under the current user's home.
    public let storePath: String

    /// Hard cap on the number of rows any single tool call may return. Caps
    /// honour the operator-supplied `limit` argument up to this value; values
    /// above it are silently clamped down. Default 1000.
    public let maxResultsHardCap: Int

    /// SQLite busy-timeout in milliseconds. Notes.app holds the database open
    /// in WAL mode; brief contention is normal during iCloud sync. Default 200ms.
    public let sqliteBusyTimeoutMs: Int32

    /// Log verbosity. Errors are always emitted to `stderr`-equivalent; this
    /// gates info-level logs only.
    public let logLevel: LogLevel

    public enum LogLevel: String, Sendable {
        case quiet, info, debug
    }

    public init(
        storePath: String = NotesBladeConfig.defaultStorePath,
        maxResultsHardCap: Int = 1000,
        sqliteBusyTimeoutMs: Int32 = 200,
        logLevel: LogLevel = .quiet
    ) throws {
        try Self.validate(storePath: storePath)
        self.storePath = storePath
        self.maxResultsHardCap = max(1, maxResultsHardCap)
        self.sqliteBusyTimeoutMs = max(0, sqliteBusyTimeoutMs)
        self.logLevel = logLevel
    }

    /// Canonical path resolved against the current process's home directory.
    public static var defaultStorePath: String {
        let home = NSHomeDirectory()
        return "\(home)/Library/Group Containers/group.com.apple.notes/NoteStore.sqlite"
    }

    /// Allowed path prefixes. Real Apple Notes is the only operational path;
    /// `/private/tmp/` is allowed exclusively to support fixture-based tests
    /// (`TemporaryDirectory` resolves under it on macOS).
    static func allowedPrefixes() -> [String] {
        let home = NSHomeDirectory()
        return [
            "\(home)/Library/Group Containers/group.com.apple.notes/",
            "/private/tmp/",
            "/tmp/",  // macOS symlink for /private/tmp; allowed for symmetry
        ]
    }

    /// Validate `storePath`. Throws `NotesBladeError.invalidStorePath` if the
    /// path falls outside the allowed prefixes.
    public static func validate(storePath: String) throws {
        // Reject path-traversal first — `..` segments would let a caller
        // sidestep the prefix check.
        if storePath.contains("..") {
            throw NotesBladeError.invalidStorePath(path: storePath)
        }
        for prefix in allowedPrefixes() {
            if storePath.hasPrefix(prefix) {
                return
            }
        }
        throw NotesBladeError.invalidStorePath(path: storePath)
    }
}
