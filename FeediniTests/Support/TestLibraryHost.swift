import Foundation

@testable import Feedini

/// Holds a library for the AI queues, without the rest of the app.
@MainActor
final class TestLibraryHost: LibraryHost {
    struct StoreFailure: Error {}

    var library: Library
    /// The stored page texts (`library.pageTextIDs` lists them).
    var pageTexts: [Article.ID: String] = [:]
    /// Storing a page text fails while set.
    var failsStoringPageTexts = false

    init(_ library: Library) {
        self.library = library
    }

    func update(_ change: (inout Library) -> Void) {
        change(&library)
    }

    /// The stored page text of the article, as `pageText` gives it.
    func storedText(_ id: Article.ID) -> String? {
        library.pageTextIDs.contains(id) ? pageTexts[id] : nil
    }

    func pageText(_ id: Article.ID) async -> String? {
        storedText(id)
    }

    func storePageText(_ text: String, for id: Article.ID) async throws {
        guard !failsStoringPageTexts else { throw StoreFailure() }
        pageTexts[id] = text
        library.pageTextIDs.insert(id)
    }
}

extension ClaudeLocator {
    /// A locator that finds claude in `~/.local/bin` (`found`) or nowhere.
    static func stub(found: Bool = true) -> ClaudeLocator {
        ClaudeLocator(homeDirectory: "/Users/me", searchPath: nil) { _ in found }
    }
}

extension MacServices {
    /// The Mac services with their model over a store in a new temporary directory and defaults of their own, not
    /// loaded (no refresh, no AI queues running). Claude calls and source pages go to the given fakes, backups to a
    /// temporary folder, sync state to a temporary file (sync never reaches iCloud). Keep the services in a local: the
    /// model holds them weakly.
    static func test(
        runner: FakeCommandRunner = FakeCommandRunner([]), extractor: FakePageExtractor = FakePageExtractor(),
        backupStore: BackupStore = .temporary()
    ) -> MacServices {
        MacServices(
            preferences: MacPreferences.test(), store: .temporary(), claudeRunner: runner, claudeLocator: .stub(),
            pageExtractor: extractor, backupStore: backupStore,
            syncStateStore: SyncStateStore(
                fileURL: FileManager.default.temporaryDirectory.appending(
                    path: "feedini-sync-\(UUID().uuidString).json")),
            syncProblem: { SyncAvailability.notInThisBuild })
    }
}

extension AppModel {
    /// A model without the Mac services (no AI, no backups) over a store in a new temporary directory and defaults
    /// of its own, not loaded. Source pages go to the given fake.
    static func test(extractor: FakePageExtractor = FakePageExtractor()) -> AppModel {
        AppModel(preferences: Preferences.test(), store: .temporary(), pageExtractor: extractor)
    }
}

extension LibraryStore {
    /// A store in a new temporary directory.
    static func temporary() -> LibraryStore {
        let directory = FileManager.default.temporaryDirectory.appending(path: "feedini-\(UUID().uuidString)")
        return LibraryStore(fileURL: directory.appending(path: "library.json"))
    }
}

extension BackupStore {
    /// A store over a new temporary folder standing in for iCloud Drive, in UTC; `drive` exists unless asked not to.
    static func temporary(device: String = "Test Mac", driveExists: Bool = true) -> BackupStore {
        let drive = FileManager.default.temporaryDirectory.appending(
            path: "feedini-drive-\(UUID().uuidString)", directoryHint: .isDirectory)
        if driveExists {
            try? FileManager.default.createDirectory(at: drive, withIntermediateDirectories: true)
        }
        return BackupStore(drive: drive, device: device, timeZone: .gmt)
    }
}

extension Preferences {
    /// Preferences over defaults of their own.
    static func test() -> Preferences {
        Preferences(defaults: UserDefaults(suiteName: "feedini-tests-\(UUID().uuidString)")!)
    }
}

extension MacPreferences {
    /// Mac preferences over defaults of their own.
    static func test() -> MacPreferences {
        MacPreferences(shared: .test())
    }
}
