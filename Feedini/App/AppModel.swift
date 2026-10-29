import Foundation
import Observation

/// Connects the layers: holds the library on the main actor, saves its changes, runs the refreshes.
@MainActor
@Observable
final class AppModel: LibraryHost {
    let preferences: Preferences
    let aiStatus = AIStatus()
    private(set) var library = Library() {
        didSet {
            if !isChangingReadState {
                cachedEntries = nil
            }
        }
    }
    private(set) var isLoaded = false
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Why the saved library couldn't be used, if it couldn't.
    private(set) var loadProblem: String?

    /// Called after every refresh (the reader drops read entries from the list then).
    @ObservationIgnored var onRefresh: (@MainActor () -> Void)?
    /// Called after every change of the library (the reader follows articles into their new stories).
    @ObservationIgnored var onLibraryChange: (@MainActor () -> Void)?

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let coordinator: RefreshCoordinator
    @ObservationIgnored private let subscriber: FeedSubscriber
    @ObservationIgnored private(set) var assignQueue: AssignQueue?
    @ObservationIgnored private(set) var summaryQueue: SummaryQueue?
    @ObservationIgnored private var scheduler: RefreshScheduler?
    @ObservationIgnored private var cachedEntries: [StoryEntry]?
    /// Set while only read state changes, so the cached entries are updated instead of rebuilt.
    @ObservationIgnored private var isChangingReadState = false
    /// The latest hand-over to the store; each waits for the previous one, so saves keep their order.
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(
        preferences: Preferences = Preferences(), store: LibraryStore = LibraryStore(),
        coordinator: RefreshCoordinator = RefreshCoordinator(), subscriber: FeedSubscriber = FeedSubscriber(),
        claudeRunner: any CommandRunning = ProcessRunner(), claudeLocator: ClaudeLocator = ClaudeLocator()
    ) {
        self.preferences = preferences
        self.store = store
        self.coordinator = coordinator
        self.subscriber = subscriber
        let configuration: @MainActor () -> AIConfiguration = { [preferences] in preferences.aiConfiguration }
        let assignQueue = AssignQueue(
            host: self, runner: claudeRunner, locator: claudeLocator, status: aiStatus, configuration: configuration)
        let summaryQueue = SummaryQueue(
            host: self, runner: claudeRunner, locator: claudeLocator, status: aiStatus, configuration: configuration)
        assignQueue.onBatchApplied = { [weak summaryQueue] in summaryQueue?.trigger() }
        self.assignQueue = assignQueue
        self.summaryQueue = summaryQueue
        if !preferences.aiEnabled {
            aiStatus.set(.off)
        }
    }

    /// All stories and loose articles, newest first.
    var entries: [StoryEntry] {
        let library = library
        if let cachedEntries {
            return cachedEntries
        }
        let entries = StoryList.allEntries(in: library, summaryLanguage: preferences.summaryLanguageCode)
        cachedEntries = entries
        return entries
    }

    /// Loads the library and starts refreshing.
    func start() async {
        guard !isLoaded else { return }
        let result = await store.load()
        library = result.library
        loadProblem = result.problem
        isLoaded = true
        let scheduler = RefreshScheduler(interval: .seconds(preferences.refreshMinutes * 60)) { [weak self] in
            await self?.refresh()
        }
        preferences.onChange = { [weak self, weak scheduler] in
            guard let self else { return }
            scheduler?.setInterval(.seconds(self.preferences.refreshMinutes * 60))
        }
        preferences.onAIChange = { [weak self] in
            // The language decides which summaries are shown.
            self?.cachedEntries = nil
            self?.organize(retryingFailed: true)
        }
        scheduler.start()
        self.scheduler = scheduler
        organize()
    }

    /// Lets the AI organize articles without a story (after a refresh, new feeds, settings changes).
    func organize(retryingFailed: Bool = false) {
        guard isLoaded else { return }
        assignQueue?.trigger(retryingFailed: retryingFailed)
        summaryQueue?.trigger(retryingFailed: retryingFailed)
    }

    func refreshNow() {
        scheduler?.refreshNow()
    }

    /// Writes pending changes (at quit).
    func flush() async {
        await saving?.value
        await store.flush()
    }

    private func refresh() async {
        guard !library.feeds.isEmpty else { return }
        isRefreshing = true
        await refresh(library.feeds)
        isRefreshing = false
        lastRefresh = .now
        onRefresh?()
        organize(retryingFailed: true)
    }

    /// Downloads the feeds and merges them into the library as it is by then.
    func refresh(_ feeds: [Feed]) async {
        let refreshes = await coordinator.refresh(feeds)
        update { library in
            let added = FeedMerge.merge(refreshes, into: &library, now: .now)
            Retention.prune(&library, now: .now)
            Log.refresh.info("\(added.count) new articles")
        }
    }

    // MARK: Feeds

    /// Checks the address and adds the feed with its articles; returns why it wasn't added.
    func subscribe(to address: String) async -> FeedSubscriber.Failure? {
        switch await subscriber.subscribe(address, existing: library.feeds.map(\.url)) {
        case .success(let subscription):
            add([subscription])
            organize()
            return nil
        case .failure(let failure):
            return failure
        }
    }

    /// Adds the feeds of an OPML file that pass the check.
    func importOPML(_ data: Data) async throws(OPML.ParseError) -> FeedSubscriber.ImportResult {
        let entries = try OPML.parse(data)
        let result = await subscriber.subscribe(entries, existing: library.feeds.map(\.url))
        add(result.added)
        organize()
        Log.feeds.info("OPML import: \(result.added.count) added, \(result.skipped.count) skipped")
        return result
    }

    func exportOPML() -> Data {
        OPML.export(library.feeds)
    }

    func removeFeeds(_ ids: Set<Feed.ID>) {
        update { library in
            for id in ids {
                library.removeFeed(id)
            }
        }
    }

    private func add(_ subscriptions: [FeedSubscriber.Subscription]) {
        guard !subscriptions.isEmpty else { return }
        update { library in
            for subscription in subscriptions
            where !library.feeds.contains(where: { FeedSubscriber.isSame($0.url, subscription.url) }) {
                let feed = Feed(title: subscription.title, url: subscription.url, siteURL: subscription.parsed.siteURL)
                library.feeds.append(feed)
                FeedMerge.merge(
                    [
                        feed.id: .updated(
                            subscription.parsed, etag: subscription.etag, lastModified: subscription.lastModified)
                    ], into: &library, now: .now)
            }
        }
    }

    // MARK: Changes

    func markRead(_ ids: [Article.ID]) {
        changeReadState(of: ids) { $0.markRead(ids, at: .now) }
    }

    func markUnread(_ ids: [Article.ID]) {
        changeReadState(of: ids) { $0.markUnread(ids) }
    }

    private func changeReadState(of ids: [Article.ID], _ change: (inout Library) -> Void) {
        guard !ids.isEmpty else { return }
        isChangingReadState = true
        defer { isChangingReadState = false }
        update(change)
        if var entries = cachedEntries {
            StoryList.updateReadState(of: ids, in: &entries, library: library)
            cachedEntries = entries
        }
    }

    /// Changes the library and saves it.
    func update(_ change: (inout Library) -> Void) {
        var library = library
        change(&library)
        guard library != self.library else { return }
        self.library = library
        onLibraryChange?()
        saving = Task { [store, previous = saving] in
            await previous?.value
            await store.save(library)
        }
    }
}
