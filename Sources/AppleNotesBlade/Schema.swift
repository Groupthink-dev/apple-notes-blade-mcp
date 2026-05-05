import Foundation

/// Documented field reference for the V10 Apple Notes schema (macOS 14+).
///
/// All metadata lives in a single master table — `ZICCLOUDSYNCINGOBJECT` —
/// with `ZTYPEUTI` discriminating between accounts, folders, notes, and
/// attachments. Body bytes live in `ZICNOTEDATA` joined via `ZNOTEDATA`.
///
/// Only the columns we actually read are documented here. Additional Z-fields
/// exist (sharing state, share invitation tokens, etc.) but are out of scope
/// for v0.1.0.
public enum NotesSchema {

    /// Apple's UTI strings stamped in `ZTYPEUTI`. We match against these
    /// rather than introspecting the column for forward-compatibility.
    public enum TypeUTI {
        public static let account = "com.apple.notes.account"
        public static let folder = "com.apple.notes.folder"
        public static let note = "com.apple.notes.note"
    }

    /// Apple's reference epoch for `ZMODIFICATIONDATE1` / `ZCREATIONDATE1`
    /// (Core Data NSDate timestamps): seconds since 2001-01-01 00:00:00 UTC.
    /// Convert to `Foundation.Date` via `Date(timeIntervalSinceReferenceDate:)`.
    public enum CoreDataEpoch {
        /// 2001-01-01 00:00:00 UTC expressed as seconds since 1970.
        public static let unixOffset: TimeInterval = 978_307_200
    }

    /// Convert an Apple Core Data timestamp (seconds since 2001-01-01 UTC) to
    /// a `Foundation.Date`. Returns `nil` for `nil` or zero inputs.
    public static func date(fromCoreData seconds: Double?) -> Date? {
        guard let s = seconds, s != 0 else { return nil }
        return Date(timeIntervalSinceReferenceDate: s)
    }
}
