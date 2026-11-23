import Foundation
import Observation

/// What only the Mac app does on top of the shared `AppModel`: the AI queues (organizing, story summaries, page
/// summaries), backups with restoring, and the update check. Owns the model; the model reaches it as its
/// `services`.
@MainActor
@Observable
final class MacServices: PlatformServices {
    let model: AppModel
    let preferences: MacPreferences
    let aiStatus: AIStatus
    let backups: Backups
    let updates: UpdateChecker
    let sync: SyncController
    @ObservationIgnored private(set) var assignQueue: AssignQueue!
    @ObservationIgnored private(set) var summaryQueue: SummaryQueue!
    @ObservationIgnored private(set) var pageQueue: PageSummaryQueue!
    /// Starting or stopping sync after the setting changed (awaited by tests).
    @ObservationIgnored private(set) var syncSettingTask: Task<Void, Never>?

    init(
        preferences: MacPreferences = MacPreferences(), store: LibraryStore = LibraryStore(),
        coordinator: RefreshCoordinator = RefreshCoordinator(), subscriber: FeedSubscriber = FeedSubscriber(),
        claudeRunner: any CommandRunning = ProcessRunner(), claudeLocator: ClaudeLocator = ClaudeLocator(),
        pageExtractor: (any PageExtracting)? = nil, backupStore: BackupStore = BackupStore(),
        syncStateStore: SyncStateStore = SyncStateStore(), updates: UpdateChecker = UpdateChecker(),
        now: @escaping @Sendable () -> Date = { .now }
    ) {
        let model = AppModel(
            preferences: preferences.shared, store: store, coordinator: coordinator, subscriber: subscriber,
            pageExtractor: pageExtractor, now: now)
        self.model = model
        self.preferences = preferences
        self.updates = updates
        aiStatus = AIStatus(pages: model.pageStatus)
        backups = Backups(store: backupStore, preferences: preferences, now: now)
        sync = SyncController(model: model, stateStore: syncStateStore, now: now)
        let configuration: @MainActor () -> AIConfiguration = { [preferences] in preferences.aiConfiguration }
        let assignQueue = AssignQueue(
            host: model, runner: claudeRunner, locator: claudeLocator, status: aiStatus, configuration: configuration)
        let summaryQueue = SummaryQueue(
            host: model, runner: claudeRunner, locator: claudeLocator, status: aiStatus, configuration: configuration)
        assignQueue.onBatchApplied = { [weak summaryQueue] in summaryQueue?.trigger() }
        self.assignQueue = assignQueue
        self.summaryQueue = summaryQueue
        pageQueue = PageSummaryQueue(
            host: model, loader: model.pageLoader, runner: claudeRunner, locator: claudeLocator, status: aiStatus,
            configuration: configuration)
        if !preferences.aiEnabled {
            aiStatus.set(.off)
        }
        model.services = self
        preferences.onAIChange = { [weak self] in
            guard let self else { return }
            self.writeSummarySettings()
            self.model.organize(retryingFailed: true)
        }
    }

    /// Loads the library, starts refreshing and the daily update check.
    func start() async {
        // Turning backups on backs up at once (the first one, or one that is due), so macOS asks for access to iCloud
        // Drive now and a problem shows right away.
        preferences.onBackupChange = { [weak self] in
            self?.backUpIfDue()
        }
        preferences.onUpdatesChange = { [weak self] in
            guard let self else { return }
            updates.setDaily(preferences.checksForUpdates)
        }
        updates.setDaily(preferences.checksForUpdates)
        preferences.onSyncChange = { [weak self] in
            guard let self else { return }
            syncSettingTask = Task { [previous = syncSettingTask] in
                await previous?.value
                await self.syncSettingChanged()
            }
        }
        sync.onTurnedOff = { [weak self] _ in
            self?.preferences.syncsWithICloud = false
        }
        // Signing in to iCloud (after syncing stopped for want of an account) starts it.
        NotificationCenter.default.addObserver(forName: .CKAccountChanged, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.preferences.syncsWithICloud, !self.sync.isRunning else { return }
                Task { await self.startSync() }
            }
        }
        await model.start()
        writeSummarySettings()
        if preferences.syncsWithICloud {
            await startSync()
        }
    }

    // MARK: Sync

    /// Starts syncing unless it can't run here, then says why.
    private func startSync() async {
        if let problem = await SyncAvailability.problem() {
            sync.setUnavailable(problem)
            return
        }
        await sync.start { [unowned self] state in CloudSyncEngine(state: state, controller: sync) }
    }

    private func syncSettingChanged() async {
        if preferences.syncsWithICloud {
            await startSync()
        } else {
            // Off: the library and the iCloud data stay; turning it on again merges them.
            await sync.stop(forgetting: true)
        }
    }

    /// Writes pending changes of the library and of syncing (at quit).
    func flush() async {
        await model.flush()
        await sync.flush()
    }

    /// Puts the summary settings into the library, where the list and other devices read them. Only once the library
    /// is loaded: a change before that would be saved over the stored library.
    private func writeSummarySettings() {
        guard model.isLoaded else { return }
        let settings = preferences.summarySettings
        if model.library.summarySettings != settings {
            model.update { $0.summarySettings = settings }
        }
    }

    // MARK: AI

    func organize(retryingFailed: Bool) {
        assignQueue.trigger(retryingFailed: retryingFailed)
        summaryQueue.trigger(retryingFailed: retryingFailed)
    }

    func refreshEnded() {
        model.organize(retryingFailed: true)
        backUpIfDue()
    }

    /// With AI on a saved link gets its summary like Shift+S; without AI only its text – every saved link would
    /// otherwise say that AI is off.
    func prepareSavedLink(_ id: Article.ID) -> Bool {
        guard preferences.aiEnabled else { return false }
        pageQueue.prepare(id)
        return true
    }

    /// T: summarizes the article's source page, loading it first unless its text is stored.
    func summarizePage(_ id: Article.ID) {
        pageQueue.summarize(id)
    }

    /// Shift+S: loads and summarizes the article's source page, the page also without AI
    /// (`PageSummaryQueue.prepare`).
    func preparePage(_ id: Article.ID) {
        pageQueue.prepare(id)
    }

    /// P on a saved link: loads its page again (`PageSummaryQueue.reload`).
    func reloadPage(_ id: Article.ID) {
        pageQueue.reload(id)
    }

    /// Whether T does anything for the article (`PageSummaryQueue.canSummarize`).
    func canSummarizePage(_ id: Article.ID) -> Bool {
        pageQueue.canSummarize(id)
    }

    // MARK: Backups

    /// An automatic backup if it is due. Not awaited: the refresh loop mustn't wait for iCloud Drive (or for the user
    /// to answer macOS asking for access to it).
    private func backUpIfDue() {
        Task { [weak self] in
            guard let self else { return }
            await backups.backUpIfDue { self.model.library }
        }
    }

    /// Whether Back Up Now does anything.
    var canBackUpNow: Bool {
        !backups.isBackingUp && !model.library.feeds.isEmpty
    }

    /// Back Up Now; a failure shows in `backups.problem`.
    func backUpNow() {
        Task { [backups, library = model.library] in try? await backups.backUp(library) }
    }

    /// Replaces the library with a backup's, and the settings too if asked. The current library is backed up first
    /// (unless it has no feeds, as on a new Mac: `Backups.backUp`); if that fails, nothing changes. Refreshing and the
    /// AI stop meanwhile and start again with the restored library; page texts stay for the articles that are in it.
    func restore(_ contents: BackupFile.Contents, settings: Bool) async throws(BackupError) {
        try await backups.backUp(model.library, kind: .beforeRestore)
        await model.stopRefreshing()
        assignQueue.cancel()
        summaryQueue.cancel()
        await assignQueue.waitUntilIdle()
        await summaryQueue.waitUntilIdle()
        model.replaceLibrary(with: contents.library)
        if settings {
            preferences.apply(contents.settings)
        }
        // Settings → AI decide on the Mac, not the backup's library.
        writeSummarySettings()
        Log.store.info(
            "Restored a backup of \(contents.created, privacy: .public) from \(contents.device, privacy: .public)")
        model.startRefreshing()
        model.organize(retryingFailed: true)
    }
}
