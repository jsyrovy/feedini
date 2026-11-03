import Foundation
import Observation

/// Backing up the library and the settings to iCloud Drive (`BackupStore`), on the main actor: automatic backups when
/// due, Back Up Now, reading backups for a restore, and the state for Settings → Backup.
///
/// Backups run one at a time; the files are written and read off the main actor.
@MainActor
@Observable
final class Backups {
    /// This Mac's newest backup, once known: written, or found when automatic backups first checked.
    private(set) var lastBackup: Date?
    /// Why the last backup failed; cleared by the next one that works.
    private(set) var problem: String?
    /// Backups being written or waiting for their turn, and the first look for the last backup.
    private var runningCount = 0

    /// Whether a backup is being written (or automatic backups look for the last one).
    var isBackingUp: Bool { runningCount > 0 }

    @ObservationIgnored let store: BackupStore
    @ObservationIgnored private let preferences: Preferences
    @ObservationIgnored private let appVersion: String
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private var knowsLastBackup = false
    /// The latest backup; each waits for the previous one.
    @ObservationIgnored private var running: Task<Void, Never>?

    init(
        store: BackupStore, preferences: Preferences,
        appVersion: String = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "",
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        self.store = store
        self.preferences = preferences
        self.appVersion = appVersion
        self.now = now
    }

    /// Backs up when automatic backups are on and the last one is older than the frequency allows. Does nothing while
    /// a backup runs (or the first look for the last one waits, e.g. for macOS asking for access to iCloud Drive), so
    /// checks don't pile up. The library is taken when the backup is written.
    func backUpIfDue(_ library: () -> Library) async {
        guard preferences.backsUp, !isBackingUp, !library().feeds.isEmpty else { return }
        if !knowsLastBackup {
            runningCount += 1
            defer { runningCount -= 1 }
            do {
                lastBackup = try await store.ownBackups().first?.created
                knowsLastBackup = true
            } catch {
                report(error)
                return
            }
        }
        guard BackupPlan.isDue(lastBackup: lastBackup, frequency: preferences.backupFrequency, now: now()) else {
            return
        }
        try? await backUp(library())
    }

    /// Writes a backup of the library and the settings, then deletes this Mac's backups that the thinning-out leaves
    /// out. A failure is also kept in `problem`. A library without feeds isn't backed up: on a new Mac, before a
    /// restore, it would thin out the backups worth restoring.
    func backUp(_ library: Library, kind: BackupFile.Kind = .regular) async throws(BackupError) {
        guard !library.feeds.isEmpty else { return }
        let previous = running
        let done = OneShotSignal()
        running = Task { await done.wait() }
        runningCount += 1
        defer {
            runningCount -= 1
            done.fire()
        }
        await previous?.value
        let contents = BackupFile.Contents(
            created: now(), device: store.device, appVersion: appVersion, settings: preferences.backedUpSettings,
            library: library)
        do {
            let backup = try await store.write(Self.encode(contents), created: contents.created, kind: kind)
            lastBackup = max(lastBackup ?? backup.created, backup.created)
            knowsLastBackup = true
            problem = nil
            Log.backup.info("Backed up \(library.articles.count) articles (\(backup.size ?? 0) bytes)")
            let own = try await store.ownBackups()
            let expired = BackupPlan.expired(own.map(\.created), now: contents.created)
            await store.delete(own.filter { expired.contains($0.created) })
        } catch {
            report(error)
            throw error
        }
    }

    /// The backups of all Macs, newest first.
    func backups() async throws(BackupError) -> [BackupStore.Backup] {
        try await store.backups()
    }

    /// Reads a backup for a restore (downloading it first if needed).
    func contents(of backup: BackupStore.Backup) async throws(BackupError) -> BackupFile.Contents {
        try await Self.decode(store.read(backup))
    }

    private func report(_ error: BackupError) {
        problem = error.message
        Log.backup.error("Backup failed: \(error.message, privacy: .public)")
    }

    @concurrent private nonisolated static func encode(
        _ contents: BackupFile.Contents
    ) async throws(BackupError) -> Data {
        try BackupFile.encode(contents)
    }

    @concurrent private nonisolated static func decode(_ data: Data) async throws(BackupError) -> BackupFile.Contents {
        try BackupFile.decode(data)
    }
}
