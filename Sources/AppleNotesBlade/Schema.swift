import Foundation

/// Documented field reference for the V10 Apple Notes schema (macOS 14+).
///
/// All metadata lives in a single master table — `ZICCLOUDSYNCINGOBJECT` —
/// with `Z_ENT` (Core Data entity ID) discriminating between accounts,
/// folders, notes, attachments, etc. Body bytes live in `ZICNOTEDATA`
/// joined via `ZNOTEDATA`.
///
/// **2026-05-07 schema correction.** v0.1.0 used `ZTYPEUTI` strings
/// (`com.apple.notes.note` etc.) as the discriminator — that column on
/// real macOS 14+ NoteStores carries attachment-MIME values like
/// `public.jpeg` / `com.apple.notes.sketch`, not entity-type discriminators.
/// The proper Core-Data discriminator is `Z_ENT` (integer FK to
/// `Z_PRIMARYKEY`). On a freshly-introspected real NoteStore:
/// - `Z_ENT = 12` → ICNote
/// - `Z_ENT = 13` → ICNoteContainer
/// - `Z_ENT = 14` → ICAccount
/// - `Z_ENT = 15` → ICFolder
/// - `Z_ENT = 9`  → ICInlineAttachment
/// - `Z_ENT = 11` → ICMedia
///
/// Z_ENT values are **per-database** — they're assigned by Core Data when
/// the schema is initialised. Most macOS 14+ NoteStores share the values
/// above, but they can drift across major macOS migrations. The real
/// schema dump in `Tests/AppleNotesBladeTests/Fixtures/real-v10-schema.sql`
/// shows the user's actual mapping; the constants below match it.
///
/// Only the columns we actually read are documented here. Additional Z-fields
/// exist (sharing state, share invitation tokens, etc.) but are out of scope
/// for v0.1.0.
public enum NotesSchema {

    /// Core Data `Z_ENT` integer constants. Match the entries in
    /// `Z_PRIMARYKEY` for a freshly-introspected macOS 14+ NoteStore.
    /// If the user's schema diverges, the runtime contract check should
    /// surface a `schemaIncompatible` error rather than silently
    /// returning empty results.
    public enum EntityID {
        public static let note: Int64 = 12
        public static let noteContainer: Int64 = 13
        public static let account: Int64 = 14
        public static let folder: Int64 = 15
        public static let inlineAttachment: Int64 = 9
        public static let media: Int64 = 11
    }

    /// Map well-known folder identifiers to friendly display names.
    /// Real Apple Notes stores folder NAMES in CloudKit metadata, not
    /// in the local SQLite — the only on-disk identifier is `ZIDENTIFIER`.
    /// User-created folders use UUIDs which we surface as-is.
    public static func folderDisplayName(fromIdentifier identifier: String?) -> String {
        guard let identifier = identifier else { return "(unknown)" }
        switch identifier {
        case "DefaultFolder-CloudKit": return "Notes"
        case "TrashFolder-CloudKit": return "Trash"
        case "SystemPaper-CloudKit": return "System Paper"
        case "RecentlyDeletedFolder-CloudKit": return "Recently Deleted"
        default: return identifier
        }
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
