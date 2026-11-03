import Foundation
import Testing

@testable import Feedini

extension ReaderTests {
    /// A backup with only the lone article, unread, and a refresh every 5 minutes.
    private var backup: BackupFile.Contents {
        BackupFile.Contents(
            created: referenceDate, device: "Old Mac", appVersion: "1.0",
            settings: BackedUpSettings(refreshMinutes: 5), library: Library(feeds: [feed], articles: [lone]))
    }

    @Test func restoringReplacesTheLibraryAfterBackingItUpAndStartsOver() async throws {
        reader.selection = .feed(feed.id)
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.expand)
        try await model.storePageText("The text of the lone article's page.", for: lone.id)
        try await model.storePageText("The text of the first article's page.", for: first.id)

        try await model.restore(backup, settings: false)

        #expect(model.library.articles.keys.sorted() == [lone.id])
        #expect(!isRead(lone))
        // Page texts stay for the articles the backup has.
        #expect(model.library.pageTextIDs == [lone.id])
        #expect(await model.pageText(lone.id) == "The text of the lone article's page.")
        #expect(model.preferences.refreshMinutes == 15)
        #expect(reader.selection == .all)
        #expect(reader.cursor == nil)
        #expect(reader.undoName == nil)
        #expect(reader.entries.map(\.title) == ["Lone"])
        // The library before the restore.
        let backups = try await model.backups.backups()
        #expect(backups.map(\.kind) == [.beforeRestore])
        let before = try await model.backups.contents(of: backups[0])
        #expect(before.library.articles.count == 3)
        #expect(before.library.articles[lone.id]?.isRead == true)
    }

    @Test func restoringTheSettingsToo() async throws {
        try await model.restore(backup, settings: true)

        #expect(model.preferences.refreshMinutes == 5)
    }

    @Test func aLibraryWithoutFeedsIsNotBackedUpBeforeARestore() async throws {
        model.update { $0 = Library() }

        try await model.restore(backup, settings: false)

        #expect(model.library == backup.library)
        #expect(try await model.backups.backups().isEmpty)
    }

    @Test func nothingIsRestoredWhenTheLibraryCantBeBackedUpFirst() async throws {
        let model = AppModel.test(backupStore: .temporary(driveExists: false))
        let library = Library(feeds: [feed], articles: [first])
        model.update { $0 = library }

        await #expect(throws: BackupError.iCloudDriveOff) { try await model.restore(backup, settings: true) }

        #expect(model.library == library)
        #expect(model.preferences.refreshMinutes == 15)
    }
}
