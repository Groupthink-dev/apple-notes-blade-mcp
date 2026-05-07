import Foundation
import SQLite

/// Read-only SQLite reader over Apple Notes' `NoteStore.sqlite`.
///
/// Concurrency model: `actor`-isolated. Holds a single `SQLite.Connection`
/// opened in read-only mode with a busy timeout (default 200ms) — Notes.app
/// keeps the database open in WAL mode while it syncs, so brief contention
/// is normal and we wait it out rather than failing.
///
/// Path discipline: never opens anything outside `Config.storePath`. Path
/// validation is enforced by `NotesBladeConfig.validate(storePath:)` at
/// config-construction time; this actor trusts the validated config.
public actor NoteStore {

    public let config: NotesBladeConfig
    private let connection: Connection

    /// Open the underlying SQLite database read-only. Throws
    /// `NotesBladeError.permissionDenied` if FDA isn't granted (the open
    /// itself returns `SQLITE_CANTOPEN`/`AUTH` rather than a POSIX EPERM,
    /// which we map back to a `permissionDenied`).
    public init(config: NotesBladeConfig) throws {
        self.config = config

        // Existence check — gives a cleaner error than letting SQLite stumble.
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: config.storePath, isDirectory: &isDirectory)
        guard exists, !isDirectory.boolValue else {
            throw NotesBladeError.storeMissing(path: config.storePath)
        }

        // We deliberately do not pass `.readWrite` — Notes.app may have a
        // write lock; we never want to be the writer; the read-only mode also
        // refuses any accidental UPDATE/INSERT we issue.
        do {
            self.connection = try Connection(config.storePath, readonly: true)
        } catch let error as Result {
            // SQLite returns `error(message:code:statement:)` cases. Map the
            // common ones; everything else falls through to sqliteError.
            throw Self.translate(sqliteError: error, path: config.storePath)
        } catch {
            throw NotesBladeError.internalError(
                "Connection init: \(String(describing: error))"
            )
        }

        connection.busyTimeout = Double(config.sqliteBusyTimeoutMs) / 1000.0
    }

    // MARK: - Read API
    //
    // These methods are what the Tools/*.swift handlers call. The tools
    // themselves shape arguments + return JSON; this actor stays type-safe.

    /// List accounts (`Z_ENT = 14`, ICAccount, in `ZICCLOUDSYNCINGOBJECT`).
    /// Real V10 has no `ZNAME` column on accounts — display name is in
    /// CloudKit metadata, not local SQLite. Surfaced as the identifier.
    public func listAccounts() throws -> [Account] {
        let sql = """
            SELECT Z_PK, ZIDENTIFIER
            FROM ZICCLOUDSYNCINGOBJECT
            WHERE Z_ENT = ?
            ORDER BY Z_PK
            """
        return try runQuery(sql, bindings: [NotesSchema.EntityID.account]) { row in
            let ident = string(row, 1)
            return Account(
                id: int64(row, 0) ?? 0,
                name: ident ?? "(account)",
                identifier: ident
            )
        }
    }

    /// List folders, optionally scoped to a single account.
    /// Real V10 stores folder names in CloudKit metadata, not local
    /// SQLite. The only on-disk handle is `ZIDENTIFIER`; well-known
    /// system folders (`DefaultFolder-CloudKit`, `TrashFolder-CloudKit`)
    /// resolve to friendly names via `NotesSchema.folderDisplayName`.
    /// User-created folders surface their UUID as the name.
    public func listFolders(accountID: Int64? = nil) throws -> [Folder] {
        var sql = """
            SELECT f.Z_PK,
                   f.ZACCOUNT3,
                   f.ZIDENTIFIER,
                   COUNT(n.Z_PK) AS note_count
            FROM ZICCLOUDSYNCINGOBJECT f
            LEFT JOIN ZICCLOUDSYNCINGOBJECT n
                   ON n.ZFOLDER = f.Z_PK
                  AND n.Z_ENT = ?
                  AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)
            WHERE f.Z_ENT = ?
            """
        var bindings: [Binding?] = [
            NotesSchema.EntityID.note,
            NotesSchema.EntityID.folder,
        ]
        if let accountID = accountID {
            sql += "  AND f.ZACCOUNT3 = ?\n"
            bindings.append(accountID)
        }
        sql += """
            GROUP BY f.Z_PK
            ORDER BY f.Z_PK
            """
        return try runQuery(sql, bindings: bindings) { row in
            let identifier: String? = string(row, 2)
            return Folder(
                id: int64(row, 0) ?? 0,
                accountID: int64(row, 1),
                name: NotesSchema.folderDisplayName(fromIdentifier: identifier),
                isDefault: identifier == "DefaultFolder-CloudKit",
                noteCount: Int(int64(row, 3) ?? 0)
            )
        }
    }

    /// List notes within a folder. Index-only — never opens `ZICNOTEDATA`.
    /// Real V10 has no `ZATTACHMENTSCOUNT` column; attachment presence
    /// is derived via correlated subquery against `Z_ENT IN (9, 11)`
    /// (ICInlineAttachment, ICMedia) joined back via `ZNOTE`.
    public func listNotes(
        folderID: Int64,
        since: Date? = nil,
        limit: Int = 100,
        offset: Int = 0
    ) throws -> [NoteSummary] {
        let cappedLimit = min(max(1, limit), config.maxResultsHardCap)
        let cappedOffset = max(0, offset)

        var sql = """
            SELECT n.Z_PK,
                   n.ZFOLDER,
                   n.ZTITLE1,
                   n.ZSNIPPET,
                   n.ZMODIFICATIONDATE1,
                   n.ZCREATIONDATE1,
                   (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT a
                     WHERE a.Z_ENT IN (?, ?) AND a.ZNOTE = n.Z_PK) AS attach_count,
                   n.ZISPINNED
            FROM ZICCLOUDSYNCINGOBJECT n
            WHERE n.Z_ENT = ?
              AND n.ZFOLDER = ?
              AND (n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)
            """
        var bindings: [Binding?] = [
            NotesSchema.EntityID.inlineAttachment,
            NotesSchema.EntityID.media,
            NotesSchema.EntityID.note,
            folderID,
        ]
        if let since = since {
            sql += "  AND n.ZMODIFICATIONDATE1 >= ?\n"
            bindings.append(since.timeIntervalSinceReferenceDate)
        }
        sql += """
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            LIMIT ? OFFSET ?
            """
        bindings.append(Int64(cappedLimit))
        bindings.append(Int64(cappedOffset))

        return try runQuery(sql, bindings: bindings) { row in
            NoteSummary(
                id: int64(row, 0) ?? 0,
                folderID: int64(row, 1),
                title: string(row, 2) ?? "",
                snippet: string(row, 3),
                modifiedAt: NotesSchema.date(fromCoreData: double(row, 4)),
                createdAt: NotesSchema.date(fromCoreData: double(row, 5)),
                hasAttachments: (int64(row, 6) ?? 0) > 0,
                isPinned: (int64(row, 7) ?? 0) != 0
            )
        }
    }

    /// Search notes by title or snippet. v0.1.0 uses a simple `LIKE` against
    /// `ZTITLE1` and `ZSNIPPET` — never opens `ZICNOTEDATA`. FTS5 against the
    /// companion `NoteStoreFTS.sqlite` is deferred (see plan open question 4).
    public func searchNotes(
        query: String,
        accountID: Int64? = nil,
        folderID: Int64? = nil,
        since: Date? = nil,
        limit: Int = 50
    ) throws -> [NoteSummary] {
        let cappedLimit = min(max(1, limit), config.maxResultsHardCap)
        let needle = "%\(query)%"

        var sql = """
            SELECT n.Z_PK,
                   n.ZFOLDER,
                   n.ZTITLE1,
                   n.ZSNIPPET,
                   n.ZMODIFICATIONDATE1,
                   n.ZCREATIONDATE1,
                   (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT a
                     WHERE a.Z_ENT IN (?, ?) AND a.ZNOTE = n.Z_PK) AS attach_count,
                   n.ZISPINNED
            FROM ZICCLOUDSYNCINGOBJECT n

            """
        var bindings: [Binding?] = [
            NotesSchema.EntityID.inlineAttachment,
            NotesSchema.EntityID.media,
        ]

        var whereClauses = [
            "n.Z_ENT = ?",
            "(n.ZMARKEDFORDELETION IS NULL OR n.ZMARKEDFORDELETION = 0)",
            "(n.ZTITLE1 LIKE ? OR n.ZSNIPPET LIKE ?)",
        ]
        bindings.append(NotesSchema.EntityID.note)
        bindings.append(needle)
        bindings.append(needle)

        if let accountID = accountID {
            sql += "  JOIN ZICCLOUDSYNCINGOBJECT f ON f.Z_PK = n.ZFOLDER\n"
            whereClauses.append("f.ZACCOUNT3 = ?")
            bindings.append(accountID)
        }
        if let folderID = folderID {
            whereClauses.append("n.ZFOLDER = ?")
            bindings.append(folderID)
        }
        if let since = since {
            whereClauses.append("n.ZMODIFICATIONDATE1 >= ?")
            bindings.append(since.timeIntervalSinceReferenceDate)
        }

        sql += "WHERE " + whereClauses.joined(separator: "\n  AND ") + "\n"
        sql += """
            ORDER BY n.ZMODIFICATIONDATE1 DESC
            LIMIT ?
            """
        bindings.append(Int64(cappedLimit))

        return try runQuery(sql, bindings: bindings) { row in
            NoteSummary(
                id: int64(row, 0) ?? 0,
                folderID: int64(row, 1),
                title: string(row, 2) ?? "",
                snippet: string(row, 3),
                modifiedAt: NotesSchema.date(fromCoreData: double(row, 4)),
                createdAt: NotesSchema.date(fromCoreData: double(row, 5)),
                hasAttachments: (int64(row, 6) ?? 0) > 0,
                isPinned: (int64(row, 7) ?? 0) != 0
            )
        }
    }

    /// Cheap metadata lookup. Reads only the index row + ZICNOTEDATA size —
    /// never inflates ZDATA. Useful when a consuming skill wants to triage
    /// "is this note worth fetching the body for?"
    public func head(id: Int64) throws -> NoteHead {
        let sql = """
            SELECT n.Z_PK,
                   n.ZFOLDER,
                   n.ZTITLE1,
                   n.ZMODIFICATIONDATE1,
                   n.ZCREATIONDATE1,
                   (SELECT COUNT(*) FROM ZICCLOUDSYNCINGOBJECT a
                     WHERE a.Z_ENT IN (?, ?) AND a.ZNOTE = n.Z_PK) AS attach_count,
                   n.ZISPINNED,
                   length(d.ZDATA) AS body_byte_length
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICNOTEDATA d ON d.Z_PK = n.ZNOTEDATA
            WHERE n.Z_PK = ?
              AND n.Z_ENT = ?
            """
        let rows = try runQuery(
            sql,
            bindings: [
                NotesSchema.EntityID.inlineAttachment,
                NotesSchema.EntityID.media,
                id,
                NotesSchema.EntityID.note,
            ]
        ) { row in
            let count = int64(row, 5) ?? 0
            return NoteHead(
                id: int64(row, 0) ?? 0,
                folderID: int64(row, 1),
                title: string(row, 2) ?? "",
                modifiedAt: NotesSchema.date(fromCoreData: double(row, 3)),
                createdAt: NotesSchema.date(fromCoreData: double(row, 4)),
                hasAttachments: count > 0,
                attachmentCount: Int(count),
                bodyByteLength: int64(row, 7).map { Int($0) },
                isPinned: (int64(row, 6) ?? 0) != 0
            )
        }
        guard let head = rows.first else {
            throw NotesBladeError.internalError("note id \(id) not found")
        }
        return head
    }

    /// Read a single note: joins ZICCLOUDSYNCINGOBJECT to ZICNOTEDATA,
    /// inflates ZDATA, runs the protobuf decoder. Returns plain text + any
    /// attachment metadata we could extract.
    ///
    /// `includeHTML` is accepted for forward-compat; v0.1.0 always returns
    /// `bodyHTML: nil` and `htmlNotImplemented: true` when set.
    public func readNote(id: Int64, includeHTML: Bool = false) throws -> Note {
        let metaSQL = """
            SELECT n.Z_PK,
                   n.ZFOLDER,
                   n.ZTITLE1,
                   n.ZMODIFICATIONDATE1,
                   n.ZCREATIONDATE1,
                   d.ZDATA
            FROM ZICCLOUDSYNCINGOBJECT n
            LEFT JOIN ZICNOTEDATA d ON d.Z_PK = n.ZNOTEDATA
            WHERE n.Z_PK = ?
              AND n.Z_ENT = ?
            """
        let rows = try runQuery(metaSQL, bindings: [id, NotesSchema.EntityID.note]) {
            row -> NoteRowSnapshot in
            NoteRowSnapshot(
                id: int64(row, 0) ?? 0,
                folderID: int64(row, 1),
                title: string(row, 2) ?? "",
                modifiedAt: NotesSchema.date(fromCoreData: double(row, 3)),
                createdAt: NotesSchema.date(fromCoreData: double(row, 4)),
                zdata: blob(row, 5)
            )
        }
        guard let snap = rows.first else {
            throw NotesBladeError.internalError("note id \(id) not found")
        }

        let decoder = ProtobufNotesDecoder(noteID: id)
        let decoded: DecodedNote
        if let zdata = snap.zdata, !zdata.isEmpty {
            decoded = try decoder.decode(zdata: zdata)
        } else {
            decoded = DecodedNote(plainText: "", attachments: [])
        }
        let attachments = decoded.attachments.enumerated().map { (i, a) in
            AttachmentMeta(id: Int64(i), filename: nil, typeUTI: a.typeUTI, byteLength: nil)
        }
        return Note(
            id: snap.id,
            folderID: snap.folderID,
            title: snap.title,
            bodyText: decoded.plainText,
            bodyHTML: nil,
            modifiedAt: snap.modifiedAt,
            createdAt: snap.createdAt,
            attachments: attachments,
            htmlNotImplemented: includeHTML
        )
    }

    // MARK: - Internals

    /// Generic query runner that hands each row to a row decoder closure.
    /// Catches SQLite errors and re-throws as `NotesBladeError`.
    ///
    /// SQLite.swift's `Statement` iterates as `[Binding?]` arrays — column
    /// access is positional via `row[index]`. The decoder closure receives
    /// each such row.
    private func runQuery<T>(
        _ sql: String,
        bindings: [Binding?],
        decode: ([Binding?]) -> T
    ) throws -> [T] {
        do {
            let stmt = try connection.prepare(sql, bindings)
            var results: [T] = []
            for row in stmt {
                results.append(decode(row))
            }
            return results
        } catch let error as Result {
            throw Self.translate(sqliteError: error, path: config.storePath)
        } catch {
            throw NotesBladeError.internalError("query: \(String(describing: error))")
        }
    }

    /// Translate a SQLite.swift `Result` into a `NotesBladeError`. Maps
    /// permission-shaped failures back to `permissionDenied` so the consumer
    /// gets a clean recovery pointer.
    private static func translate(sqliteError: Result, path: String) -> NotesBladeError {
        let (message, code): (String, Int32)
        switch sqliteError {
        case .error(let m, let c, _):
            (message, code) = (m, c)
        case .extendedError(let m, let extended, _):
            // Extended codes encode the primary code in the low 8 bits.
            (message, code) = (m, extended & 0xff)
        }
        // SQLITE_AUTH = 23, SQLITE_PERM = 3, SQLITE_CANTOPEN = 14.
        // Apple's TCC layer typically surfaces SQLITE_CANTOPEN with the
        // string "unable to open database file" when FDA is missing.
        if code == 23 || code == 3 {
            return .permissionDenied(path: path)
        }
        if code == 14, message.localizedCaseInsensitiveContains("unable to open") {
            return .permissionDenied(path: path)
        }
        // SQLITE_BUSY = 5, SQLITE_LOCKED = 6.
        if code == 5 || code == 6 {
            return .storeLocked
        }
        return .sqliteError(code: code, message: message)
    }

    // MARK: - Row helpers
    //
    // SQLite.swift yields each row as `[Binding?]`. These helpers normalise
    // the coercions we need (Int64 / Double / String) and tolerate NULL.

    private func int64(_ row: [Binding?], _ index: Int) -> Int64? {
        guard index < row.count, let value = row[index] else { return nil }
        if let i = value as? Int64 { return i }
        if let i = value as? Int { return Int64(i) }
        return nil
    }

    private func double(_ row: [Binding?], _ index: Int) -> Double? {
        guard index < row.count, let value = row[index] else { return nil }
        if let d = value as? Double { return d }
        if let i = value as? Int64 { return Double(i) }
        if let i = value as? Int { return Double(i) }
        return nil
    }

    private func string(_ row: [Binding?], _ index: Int) -> String? {
        guard index < row.count, let value = row[index] else { return nil }
        return value as? String
    }

    private func blob(_ row: [Binding?], _ index: Int) -> Data? {
        guard index < row.count, let value = row[index] else { return nil }
        if let blob = value as? Blob {
            return Data(blob.bytes)
        }
        return nil
    }
}

/// Internal snapshot used by `readNote` so the runQuery decoder closure can
/// return a value type without touching SQLite types outside the actor.
private struct NoteRowSnapshot {
    let id: Int64
    let folderID: Int64?
    let title: String
    let modifiedAt: Date?
    let createdAt: Date?
    let zdata: Data?
}
