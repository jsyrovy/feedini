import Foundation
import Testing

@testable import Feedini

struct BackupStoreTests {
    private let store = BackupStore.temporary()

    private func remove() {
        try? FileManager.default.removeItem(at: store.drive)
    }

    @Test func writesIntoTheFolderOfThisMacAndListsAllMacsNewestFirst() async throws {
        defer { remove() }
        let other = BackupStore(drive: store.drive, device: "Other Mac", timeZone: .gmt)

        let first = try await store.write(Data("first".utf8), created: .hours(0), kind: .regular)
        _ = try await other.write(Data("other".utf8), created: .hours(1), kind: .regular)
        _ = try await store.write(Data("newest".utf8), created: .hours(2), kind: .beforeRestore)

        #expect(first.url.path.hasSuffix("/Feedini/Backups/Test Mac/2026-10-29_12-00-00.feedinibackup"))
        #expect(first.size == 5)
        let backups = try await store.backups()
        #expect(backups.map(\.created) == [.hours(2), .hours(1), .hours(0)])
        #expect(backups.map(\.device) == ["Test Mac", "Other Mac", "Test Mac"])
        #expect(backups.map(\.kind) == [.beforeRestore, .regular, .regular])
        #expect(backups.map(\.size) == [6, 5, 5])
        #expect(backups.allSatisfy { $0.isDownloaded })
        #expect(try await store.ownBackups().map(\.created) == [.hours(2), .hours(0)])
        #expect(try await store.read(backups[1]) == Data("other".utf8))
    }

    @Test func listsNothingBeforeTheFirstBackupAndSkipsOtherFiles() async throws {
        defer { remove() }
        #expect(try await store.backups().isEmpty)

        let backup = try await store.write(Data("backup".utf8), created: .hours(0), kind: .regular)
        let folder = backup.url.deletingLastPathComponent()
        try Data().write(to: folder.appending(path: "notes.txt"))
        try Data().write(to: folder.deletingLastPathComponent().appending(path: "loose.feedinibackup"))
        // The placeholder of a backup kept only in iCloud.
        let placeholder = ".\(BackupFile.name(created: .hours(-1), kind: .regular, timeZone: .gmt)).icloud"
        try Data().write(to: folder.appending(path: placeholder))

        let backups = try await store.backups()

        #expect(backups.map(\.created) == [.hours(0), .hours(-1)])
        #expect(backups[1].url.lastPathComponent == "2026-10-29_11-00-00.feedinibackup")
        #expect(!backups[1].isDownloaded)
        #expect(backups[1].size == nil)
    }

    @Test func deletesBackups() async throws {
        defer { remove() }
        let old = try await store.write(Data("old".utf8), created: .hours(0), kind: .regular)
        _ = try await store.write(Data("new".utf8), created: .hours(1), kind: .regular)

        await store.delete([old])

        #expect(try await store.backups().map(\.created) == [.hours(1)])
    }

    @Test func saysWhenICloudDriveIsOff() async {
        let store = BackupStore.temporary(driveExists: false)

        await #expect(throws: BackupError.iCloudDriveOff) {
            _ = try await store.write(Data(), created: .hours(0), kind: .regular)
        }
        await #expect(throws: BackupError.iCloudDriveOff) { _ = try await store.backups() }
    }

    @Test func saysWhenAccessIsDenied() async throws {
        defer { remove() }
        let backup = try await store.write(Data("backup".utf8), created: .hours(0), kind: .regular)
        let manager = FileManager.default
        let folder = backup.url.deletingLastPathComponent()
        try manager.setAttributes([.posixPermissions: 0o500], ofItemAtPath: folder.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path) }

        await #expect(throws: BackupError.noAccess) {
            _ = try await store.write(Data(), created: .hours(1), kind: .regular)
        }

        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: folder.path)
        await #expect(throws: BackupError.noAccess) { _ = try await store.backups() }
        try manager.setAttributes([.posixPermissions: 0o000], ofItemAtPath: store.directory.path)
        defer { try? manager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: store.directory.path) }
        await #expect(throws: BackupError.noAccess) { _ = try await store.backups() }
    }

    @Test func reportsAFailedRead() async throws {
        defer { remove() }
        let backup = try await store.write(Data("backup".utf8), created: .hours(0), kind: .regular)
        try FileManager.default.removeItem(at: backup.url)

        await #expect {
            _ = try await store.read(backup)
        } throws: { error in
            if case .failed = error as? BackupError { true } else { false }
        }
    }

    @Test func turnsTheComputerNameIntoAFolderName() {
        #expect(BackupStore.folderName("Jane's MacBook Pro") == "Jane's MacBook Pro")
        #expect(BackupStore.folderName(" A/B:C ") == "A-B-C")
        #expect(BackupStore.folderName("") == "Mac")
        #expect(BackupStore.folderName(".hidden") == "Mac")
        #expect(!BackupStore.computerName.isEmpty)
        #expect(BackupStore.iCloudDrive.path.hasSuffix("/Library/Mobile Documents/com~apple~CloudDocs"))
    }
}
