import Foundation
import Testing

@testable import Feedini

struct BackupFileTests {
    private func contents() -> BackupFile.Contents {
        let folder = Folder(name: "Daily")
        let feed = Feed.stub("Tech", folder: folder.id)
        let saved = Article.stub("Saved", feed: feed.id, savedAt: .hours(1))
        let other = Article.stub("Other", feed: feed.id, hours: 1)
        var library = Library(
            feeds: [feed], articles: [saved, other],
            stories: [Story(title: "Story", articleIDs: [saved.id, other.id], savedAt: .hours(2))], folders: [folder])
        library.pageTextIDs = [saved.id]
        return BackupFile.Contents(
            created: referenceDate, device: "Test Mac", appVersion: "1.0",
            settings: BackedUpSettings(refreshMinutes: 30, aiEffort: "high", summaryLanguage: "cs"), library: library)
    }

    @Test func namesBackupsByTheirDateAndKind() throws {
        let regular = BackupFile.name(created: referenceDate, kind: .regular, timeZone: .gmt)
        let beforeRestore = BackupFile.name(created: referenceDate, kind: .beforeRestore, timeZone: .gmt)

        #expect(regular == "2026-10-29_12-00-00.feedinibackup")
        #expect(beforeRestore == "2026-10-29_12-00-00_before-restore.feedinibackup")
        #expect(BackupFile.parse(regular, timeZone: .gmt)?.created == referenceDate)
        #expect(BackupFile.parse(regular, timeZone: .gmt)?.kind == .regular)
        #expect(BackupFile.parse(beforeRestore, timeZone: .gmt)?.kind == .beforeRestore)
        // The placeholder of a file kept only in iCloud.
        #expect(BackupFile.withoutPlaceholder(".\(regular).icloud") == regular)
        #expect(BackupFile.withoutPlaceholder(regular) == regular)
        for other in [
            "library.json", ".DS_Store", "notes.feedinibackup", "2026-10-29_12-00-00_copy.feedinibackup",
            "2026-10-29 12-00-00.feedinibackup",
        ] {
            #expect(BackupFile.parse(other, timeZone: .gmt) == nil)
        }
    }

    @Test func keepsTheLibraryAndSettingsWithoutPageTexts() throws {
        let contents = contents()

        let data = try BackupFile.encode(contents)
        let decoded = try BackupFile.decode(data)

        var expected = contents
        expected.library.pageTextIDs = []
        #expect(decoded == expected)
        // Compressed, not plain JSON.
        #expect(!String(decoding: data, as: UTF8.self).contains("feedini-backup"))
    }

    @Test func summarizesWhatTheBackupHolds() {
        var contents = contents()
        #expect(contents.summary == "1 feed, 2 articles, 2 saved")

        contents.library = Library(feeds: [.stub(), .stub("Other")], articles: [])
        #expect(contents.summary == "2 feeds, 0 articles")
    }

    @Test func rejectsOtherFilesAndNewerBackups() throws {
        #expect(throws: BackupError.notABackup) { try BackupFile.decode(Data("not compressed".utf8)) }
        let otherJSON = try (Data(#"{"version": 1}"#.utf8) as NSData).compressed(using: .zlib) as Data
        #expect(throws: BackupError.notABackup) { try BackupFile.decode(otherJSON) }

        // Keys are sorted: the format's version comes last, the library's closes the library.
        let json = try json(of: contents())
        #expect(json.hasSuffix(#","version":1}"#))
        let newerFormat = try compressed(String(json.dropLast(2)) + "2}")
        #expect(throws: BackupError.newerVersion) { try BackupFile.decode(newerFormat) }
        let libraryVersion = #""version":\#(LibraryStore.schemaVersion)},"settings""#
        #expect(json.contains(libraryVersion))
        let newerLibrary = try compressed(json.replacing(libraryVersion, with: #""version":99},"settings""#))
        #expect(throws: BackupError.newerVersion) { try BackupFile.decode(newerLibrary) }
    }

    private func json(of contents: BackupFile.Contents) throws -> String {
        let data = try BackupFile.encode(contents)
        return String(decoding: try (data as NSData).decompressed(using: .zlib) as Data, as: UTF8.self)
    }

    private func compressed(_ json: String) throws -> Data {
        try (Data(json.utf8) as NSData).compressed(using: .zlib) as Data
    }

    @Test func errorsHaveMessagesForTheUser() {
        #expect(BackupError.iCloudDriveOff.message.contains("iCloud Drive is off"))
        #expect(BackupError.noAccess.message == "Feedini has no access to iCloud Drive.")
        #expect(BackupError.notABackup.message.contains("isn't a Feedini backup"))
        #expect(BackupError.newerVersion.message.contains("newer version"))
        #expect(BackupError.failed("Disk full.").message == "Disk full.")
    }
}
