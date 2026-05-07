import Foundation
import SQLite
@testable import AppleNotesBlade

/// Builder that materialises a synthetic `NoteStore.sqlite` on disk under the
/// tmp directory. Tests get a fully-populated minimal V10 schema with a few
/// accounts / folders / notes, plus a config that points at it.
///
/// Why not `:memory:`? — `Connection(":memory:", readonly: true)` is contradictory;
/// SQLite's read-only mode requires a real file. We materialise to a temp file
/// (under `/private/tmp/`) and clean up in tearDown.
enum SampleNoteStoreBuilder {

    /// Build a fresh sample store at a temp path. Returns the absolute path.
    /// Caller is responsible for deleting the file when done.
    static func makeSampleStore() throws -> String {
        let dir = "/private/tmp/apple-notes-blade-tests-\(UUID().uuidString)"
        try FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true)
        let path = "\(dir)/NoteStore.sqlite"

        // Open writable to create + populate, then close. The actor under
        // test will reopen read-only.
        let db = try Connection(path)
        try createSchema(db)
        try insertSampleData(db)
        try db.run("PRAGMA wal_checkpoint(TRUNCATE);")
        // Connection deinit closes; nothing more to do.
        return path
    }

    /// Build a config pointing at a fresh sample store.
    static func makeSampleConfig() throws -> (config: NotesBladeConfig, path: String) {
        let path = try makeSampleStore()
        let config = try NotesBladeConfig(storePath: path, maxResultsHardCap: 1000)
        return (config, path)
    }

    /// Minimal V10 schema aligned with **real macOS 14+ NoteStore.sqlite**.
    ///
    /// **2026-05-07 schema correction.** v0.1.0 fixtures used `ZTYPEUTI`
    /// strings (`com.apple.notes.note` etc.) as the entity discriminator
    /// and assumed a `ZATTACHMENTSCOUNT` column on notes. Real V10 uses
    /// `Z_ENT` (Core Data integer entity ID) and has no per-note
    /// attachment count — attachments are separate rows linked back via
    /// `ZNOTE` FK. Folders also have no name column at all (CloudKit
    /// metadata only); only `ZIDENTIFIER` is on-disk.
    ///
    /// The full real-schema reference is in
    /// `Tests/AppleNotesBladeTests/Fixtures/real-v10-schema.sql`.
    private static func createSchema(_ db: Connection) throws {
        try db.run(
            """
            CREATE TABLE ZICCLOUDSYNCINGOBJECT (
                Z_PK INTEGER PRIMARY KEY,
                Z_ENT INTEGER NOT NULL DEFAULT 0,
                ZIDENTIFIER TEXT,
                ZTITLE1 TEXT,
                ZSNIPPET TEXT,
                ZACCOUNT3 INTEGER,
                ZFOLDER INTEGER,
                ZNOTE INTEGER,
                ZNOTEDATA INTEGER,
                ZMODIFICATIONDATE1 REAL,
                ZCREATIONDATE1 REAL,
                ZISPINNED INTEGER DEFAULT 0,
                ZMARKEDFORDELETION INTEGER DEFAULT 0
            );
            """)
        try db.run("""
            CREATE TABLE ZICNOTEDATA (
                Z_PK INTEGER PRIMARY KEY,
                ZNOTE INTEGER,
                ZDATA BLOB
            );
            """)
    }

    /// Sample fixture: 1 account (Z_ENT=14), 2 folders (Z_ENT=15),
    /// 3 notes (Z_ENT=12), 1 attachment row (Z_ENT=11) on note 102 so
    /// hasAttachments derivation can be tested.
    /// Apple Core Data timestamps = seconds since 2001-01-01 UTC.
    /// Use a fixed reference time so tests are deterministic.
    private static func insertSampleData(_ db: Connection) throws {
        let modDate1: Double = 770_000_000  // ~2025-06
        let modDate2: Double = 770_100_000
        let modDate3: Double = 770_200_000

        // Account (Z_PK = 1, Z_ENT = 14 = ICAccount)
        try db.run("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZIDENTIFIER)
            VALUES (1, 14, 'icloud-account-uuid');
            """)

        // Folders (Z_PK = 10, 11; Z_ENT = 15 = ICFolder).
        // Real V10 has NO folder-name column; ZIDENTIFIER is the only
        // on-disk handle. NotesSchema.folderDisplayName resolves
        // 'DefaultFolder-CloudKit' → 'Notes' for tests.
        try db.run("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZIDENTIFIER, ZACCOUNT3)
            VALUES
                (10, 15, 'DefaultFolder-CloudKit', 1),
                (11, 15, 'recipes-uuid', 1);
            """)

        // Notes (Z_PK = 100, 101, 102; Z_ENT = 12 = ICNote)
        try db.run("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZTITLE1, ZSNIPPET, ZFOLDER, ZNOTEDATA,
                 ZMODIFICATIONDATE1, ZCREATIONDATE1, ZISPINNED)
            VALUES
                (100, 12, 'Hello world', 'Hello world body...', 10, 200, ?, ?, 0),
                (101, 12, 'Recipe — pesto', 'Basil, pine nuts...',  11, 201, ?, ?, 1),
                (102, 12, 'Shopping list',  'Milk, eggs, bread',    10, 202, ?, ?, 0);
            """,
            modDate1, modDate1,
            modDate2, modDate2,
            modDate3, modDate3
        )

        // One attachment row pointing at note 102 (Z_ENT = 11 = ICMedia).
        // Lets hasAttachments test the COUNT-via-subquery path.
        try db.run("""
            INSERT INTO ZICCLOUDSYNCINGOBJECT
                (Z_PK, Z_ENT, ZNOTE)
            VALUES (300, 11, 102);
            """)

        // ZICNOTEDATA rows with real gzip+protobuf-encoded ZDATA blobs.
        // Each blob carries a known body string so readNote tests can verify
        // round-trip fidelity. Note 102 also has an embedded attachment UUID.
        let body100 = "Hello world body — this is the canonical first note."
        let body101 = "Recipe — pesto. Basil, pine nuts, parmesan, garlic, olive oil."
        let body102 = "Shopping list. Milk, eggs, bread, attached photo of fridge."
        let attachmentUUID = "F4DCEC4A-1234-5678-90AB-CDEF12345678"

        let blob100 = ProtobufFixtures.makeNoteBody(body100)
        let blob101 = ProtobufFixtures.makeNoteBody(body101)
        let blob102 = ProtobufFixtures.makeNoteBody(body102, attachmentUUID: attachmentUUID)

        try db.run(
            "INSERT INTO ZICNOTEDATA (Z_PK, ZNOTE, ZDATA) VALUES (?, ?, ?);",
            [200, 100, Blob(bytes: [UInt8](blob100))]
        )
        try db.run(
            "INSERT INTO ZICNOTEDATA (Z_PK, ZNOTE, ZDATA) VALUES (?, ?, ?);",
            [201, 101, Blob(bytes: [UInt8](blob101))]
        )
        try db.run(
            "INSERT INTO ZICNOTEDATA (Z_PK, ZNOTE, ZDATA) VALUES (?, ?, ?);",
            [202, 102, Blob(bytes: [UInt8](blob102))]
        )
    }

    /// Body text fixtures — exposed so tests can assert round-trip equality
    /// without duplicating string literals.
    static let body100 = "Hello world body — this is the canonical first note."
    static let body101 = "Recipe — pesto. Basil, pine nuts, parmesan, garlic, olive oil."
    static let body102 = "Shopping list. Milk, eggs, bread, attached photo of fridge."
    static let attachmentUUID = "F4DCEC4A-1234-5678-90AB-CDEF12345678"

    static func cleanup(path: String) {
        let dir = (path as NSString).deletingLastPathComponent
        try? FileManager.default.removeItem(atPath: dir)
    }
}
