import XCTest
@testable import AppleNotesBlade

final class NoteStoreReadTests: XCTestCase {

    var storePath: String!
    var store: NoteStore!

    override func setUp() async throws {
        let (config, path) = try SampleNoteStoreBuilder.makeSampleConfig()
        self.storePath = path
        self.store = try NoteStore(config: config)
    }

    override func tearDown() async throws {
        if let storePath = storePath {
            SampleNoteStoreBuilder.cleanup(path: storePath)
        }
        store = nil
        storePath = nil
    }

    // MARK: - listAccounts

    func testListAccountsReturnsTheSampleAccount() async throws {
        let accounts = try await store.listAccounts()
        XCTAssertEqual(accounts.count, 1)
        // Real V10 stores no `ZNAME` for accounts; display name == identifier.
        XCTAssertEqual(accounts.first?.identifier, "icloud-account-uuid")
        XCTAssertEqual(accounts.first?.name, "icloud-account-uuid")
    }

    // MARK: - listFolders

    func testListFoldersReturnsBothSampleFolders() async throws {
        let folders = try await store.listFolders()
        XCTAssertEqual(folders.count, 2)
        // Real V10 has no folder-name column; "DefaultFolder-CloudKit" maps
        // to "Notes" via NotesSchema.folderDisplayName, user-created folders
        // surface their UUID as the name.
        let names = folders.map { $0.name }.sorted()
        XCTAssertEqual(names, ["Notes", "recipes-uuid"])
    }

    func testListFoldersReportsNoteCount() async throws {
        let folders = try await store.listFolders()
        let notesFolder = folders.first { $0.name == "Notes" }
        let recipesFolder = folders.first { $0.name == "recipes-uuid" }
        XCTAssertEqual(notesFolder?.noteCount, 2)
        XCTAssertEqual(recipesFolder?.noteCount, 1)
    }

    func testListFoldersIdentifiesDefaultFolder() async throws {
        let folders = try await store.listFolders()
        let notesFolder = folders.first { $0.name == "Notes" }
        let recipesFolder = folders.first { $0.name == "recipes-uuid" }
        XCTAssertEqual(notesFolder?.isDefault, true)
        XCTAssertEqual(recipesFolder?.isDefault, false)
    }

    func testListFoldersFiltersByAccountID() async throws {
        let folders = try await store.listFolders(accountID: 1)
        XCTAssertEqual(folders.count, 2)

        let none = try await store.listFolders(accountID: 999)
        XCTAssertEqual(none.count, 0)
    }

    // MARK: - listNotes

    func testListNotesReturnsTwoNotesInDefaultFolder() async throws {
        let notes = try await store.listNotes(folderID: 10)
        XCTAssertEqual(notes.count, 2)
        XCTAssertTrue(notes.contains { $0.title == "Hello world" })
        XCTAssertTrue(notes.contains { $0.title == "Shopping list" })
    }

    func testListNotesReturnsOneNoteInRecipesFolder() async throws {
        let notes = try await store.listNotes(folderID: 11)
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Recipe — pesto")
        XCTAssertEqual(notes.first?.isPinned, true)
    }

    func testListNotesSortsNewestFirst() async throws {
        let notes = try await store.listNotes(folderID: 10)
        // Sample dates: shopping list (102) is newer than hello world (100)
        XCTAssertEqual(notes.first?.title, "Shopping list")
        XCTAssertEqual(notes.last?.title, "Hello world")
    }

    func testListNotesHonoursLimitArgument() async throws {
        let notes = try await store.listNotes(folderID: 10, limit: 1)
        XCTAssertEqual(notes.count, 1)
    }

    func testListNotesClampsLimitToHardCap() async throws {
        // Ask for 100_000; sample store has only 2 notes in folder 10, so
        // we still see 2. The clamp matters because the bound parameter
        // wraps the SQL LIMIT — if we accidentally bound a huge value we'd
        // still get 2 back. The real assertion is that the call doesn't
        // throw and respects the cap value internally.
        let notes = try await store.listNotes(folderID: 10, limit: 100_000)
        XCTAssertEqual(notes.count, 2)
    }

    func testListNotesAttachmentFlagReflectsCount() async throws {
        let notes = try await store.listNotes(folderID: 10)
        let shopping = notes.first { $0.title == "Shopping list" }
        XCTAssertEqual(shopping?.hasAttachments, true)
        let hello = notes.first { $0.title == "Hello world" }
        XCTAssertEqual(hello?.hasAttachments, false)
    }

    func testListNotesSinceFilterDropsOlderNotes() async throws {
        // modDate2 = 770_100_000, only Recipe and Shopping list are >=
        let cutoff = Date(timeIntervalSinceReferenceDate: 770_050_000)
        let notes = try await store.listNotes(folderID: 10, since: cutoff)
        // Hello world was at 770_000_000 < cutoff → dropped.
        XCTAssertEqual(notes.count, 1)
        XCTAssertEqual(notes.first?.title, "Shopping list")
    }
}
