import Foundation
import Synchronization
import Testing

@testable import Feedini

@MainActor
struct BackupsTests {
    private let store = BackupStore.temporary()
    private let preferences = Preferences.test()
    private let clock = TestClock()
    private let library = Library(feeds: [.stub()], articles: [])

    private func backups(store: BackupStore? = nil) -> Backups {
        Backups(store: store ?? self.store, preferences: preferences, appVersion: "1.0") { [clock] in clock.now }
    }

    private func setTime(hours: Double) {
        clock.now = .hours(hours)
    }

    private func remove() {
        try? FileManager.default.removeItem(at: store.drive)
    }

    @Test func backsUpTheLibraryAndSettings() async throws {
        defer { remove() }
        let backups = backups()
        preferences.refreshMinutes = 30
        #expect(backups.lastBackup == nil)

        try await backups.backUp(library)

        #expect(backups.lastBackup == referenceDate)
        #expect(!backups.isBackingUp)
        let backup = try #require(try await store.backups().first)
        let contents = try await backups.contents(of: backup)
        #expect(contents.library == library)
        #expect(contents.settings.refreshMinutes == 30)
        #expect(contents.device == "Test Mac")
        #expect(contents.appVersion == "1.0")
        #expect(contents.created == referenceDate)
    }

    @Test func backsUpAutomaticallyOnlyWhenOnDueAndWithFeeds() async throws {
        defer { remove() }
        let backups = backups()

        await backups.backUpIfDue { library }
        #expect(try await store.backups().isEmpty)

        preferences.backsUp = true
        await backups.backUpIfDue { Library() }
        #expect(try await store.backups().isEmpty)

        await backups.backUpIfDue { library }
        setTime(hours: 20)
        await backups.backUpIfDue { library }
        #expect(try await store.backups().map(\.created) == [referenceDate])

        setTime(hours: 23)
        await backups.backUpIfDue { library }
        #expect(try await store.backups().map(\.created) == [.hours(23), referenceDate])
    }

    @Test func findsTheLastBackupOfThisMacBeforeTheFirstAutomaticOne() async throws {
        defer { remove() }
        let other = BackupStore(drive: store.drive, device: "Other Mac", timeZone: .gmt)
        _ = try await store.write(Data(), created: .hours(-0.5), kind: .regular)
        preferences.backsUp = true
        preferences.backupFrequency = .hourly

        let notDue = backups()
        await notDue.backUpIfDue { library }
        #expect(notDue.lastBackup == .hours(-0.5))
        #expect(try await store.backups().count == 1)

        // Another Mac's backups don't count.
        setTime(hours: 1)
        _ = try await other.write(Data(), created: .hours(0.9), kind: .regular)
        let due = backups()
        await due.backUpIfDue { library }
        #expect(due.lastBackup == .hours(1))
        #expect(try await store.ownBackups().map(\.created) == [.hours(1), .hours(-0.5)])
    }

    @Test func thinsOutOnlyThisMacsBackups() async throws {
        defer { remove() }
        let other = BackupStore(drive: store.drive, device: "Other Mac", timeZone: .gmt)
        for hours in [-30.0, -34] {
            _ = try await store.write(Data(), created: .hours(hours), kind: .regular)
            _ = try await other.write(Data(), created: .hours(hours), kind: .regular)
        }

        try await backups().backUp(library)

        // Of two backups of the same day, older than a day, the newer one stays.
        #expect(try await store.ownBackups().map(\.created) == [referenceDate, .hours(-30)])
        #expect(try await other.ownBackups().count == 2)
    }

    @Test func keepsTheProblemUntilABackupWorks() async throws {
        let missing = BackupStore.temporary(driveExists: false)
        let backups = backups(store: missing)
        preferences.backsUp = true

        await backups.backUpIfDue { library }
        #expect(backups.problem == BackupError.iCloudDriveOff.message)
        await #expect(throws: BackupError.iCloudDriveOff) { try await backups.backUp(library) }
        #expect(backups.problem == BackupError.iCloudDriveOff.message)
        await #expect(throws: BackupError.iCloudDriveOff) { _ = try await backups.backups() }

        try FileManager.default.createDirectory(at: missing.drive, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: missing.drive) }
        try await backups.backUp(library)
        #expect(backups.problem == nil)
    }

    @Test func runsBackupsOneAfterAnother() async throws {
        defer { remove() }
        let backups = backups()

        async let first: Void = backups.backUp(library)
        async let second: Void = backups.backUp(library, kind: .beforeRestore)
        _ = try await (first, second)

        #expect(try await store.backups().count == 2)
        #expect(!backups.isBackingUp)
    }

    @Test func aLibraryWithoutFeedsIsNotBackedUp() async throws {
        defer { remove() }

        try await backups().backUp(Library())

        #expect(try await store.backups().isEmpty)
    }

    @Test func reportsADamagedBackup() async throws {
        defer { remove() }
        let backup = try await store.write(Data("damaged".utf8), created: .hours(0), kind: .regular)

        await #expect(throws: BackupError.notABackup) { _ = try await backups().contents(of: backup) }
    }
}

/// A clock that tests set by hand.
private final class TestClock: Sendable {
    private let date = Mutex(referenceDate)

    var now: Date {
        get { date.withLock { $0 } }
        set { date.withLock { $0 = newValue } }
    }
}
