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
            // Comparing unchanged collections is cheap (they share their storage).
            if library.articles != oldValue.articles || library.stories != oldValue.stories {
                entriesCache = nil
            } else if entriesCache != nil, library.feeds != oldValue.feeds || library.folders != oldValue.folders {
                // Moving feeds between folders changes only the folder counts.
                entriesCache?.setFolders(library.folderIDsByFeed())
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
    @ObservationIgnored private(set) var pageQueue: PageSummaryQueue?
    @ObservationIgnored private var scheduler: RefreshScheduler?
    @ObservationIgnored private var entriesCache: EntriesCache?
    /// The latest hand-over to the store; each waits for the previous one, so saves keep their order.
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(
        preferences: Preferences = Preferences(), store: LibraryStore = LibraryStore(),
        coordinator: RefreshCoordinator = RefreshCoordinator(), subscriber: FeedSubscriber = FeedSubscriber(),
        claudeRunner: any CommandRunning = ProcessRunner(), claudeLocator: ClaudeLocator = ClaudeLocator(),
        pageExtractor: (any PageExtracting)? = nil
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
        pageQueue = PageSummaryQueue(
            host: self, extractor: pageExtractor ?? PageExtractor(), runner: claudeRunner, locator: claudeLocator,
            status: aiStatus, configuration: configuration)
        if !preferences.aiEnabled {
            aiStatus.set(.off)
        }
    }

    /// All stories and loose articles, newest first.
    var entries: [StoryEntry] { cache.entries }

    /// Unread entries per sidebar item.
    var unreadCounts: StoryList.Counts { cache.counts }

    /// The folder of every feed in one.
    var folderIDsByFeed: [Feed.ID: Folder.ID] { cache.folders }

    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        let cache = cache
        return cache.index[id].map { cache.entries[$0] }
    }

    /// Built when first needed after the articles, the stories or the summary settings changed.
    private var cache: EntriesCache {
        let library = library
        let language = preferences.summaryLanguageCode
        let singleArticles = preferences.singleArticleSummaries
        if let entriesCache, entriesCache.language == language, entriesCache.singleArticles == singleArticles {
            return entriesCache
        }
        let cache = EntriesCache(
            entries: StoryList.allEntries(in: library, summaryLanguage: language, singleArticles: singleArticles),
            folders: library.folderIDsByFeed(), language: language, singleArticles: singleArticles)
        entriesCache = cache
        return cache
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

    /// Checks the address and adds the feed with its articles into the folder; returns why it wasn't added.
    func subscribe(to address: String, folder: Folder.ID? = nil) async -> FeedSubscriber.Failure? {
        switch await subscriber.subscribe(address, existing: library.feeds.map(\.url)) {
        case .success(let subscription):
            add([subscription], folder: folder)
            organize()
            return nil
        case .failure(let failure):
            return failure
        }
    }

    /// Adds the feeds of an OPML file that pass the check, into the folders named after their categories.
    func importOPML(_ data: Data) async throws(OPML.ParseError) -> FeedSubscriber.ImportResult {
        let entries = try OPML.parse(data)
        let result = await subscriber.subscribe(entries, existing: library.feeds.map(\.url))
        add(result.added)
        organize()
        Log.feeds.info("OPML import: \(result.added.count) added, \(result.skipped.count) skipped")
        return result
    }

    func exportOPML() -> Data {
        OPML.export(library.feeds, folders: library.folders)
    }

    func removeFeeds(_ ids: Set<Feed.ID>) {
        update { library in
            for id in ids {
                library.removeFeed(id)
            }
        }
    }

    /// Adds the feeds into the folder, or (OPML) into the folder named as their category.
    private func add(_ subscriptions: [FeedSubscriber.Subscription], folder: Folder.ID? = nil) {
        guard !subscriptions.isEmpty else { return }
        update { library in
            for subscription in subscriptions
            where !library.feeds.contains(where: { FeedSubscriber.isSame($0.url, subscription.url) }) {
                let feed = Feed(title: subscription.title, url: subscription.url, siteURL: subscription.parsed.siteURL)
                library.feeds.append(feed)
                library.moveFeeds([feed.id], to: folder ?? subscription.folder.flatMap { library.folderID(named: $0) })
                FeedMerge.merge(
                    [
                        feed.id: .updated(
                            subscription.parsed, etag: subscription.etag, lastModified: subscription.lastModified)
                    ], into: &library, now: .now)
            }
        }
    }

    // MARK: Folders

    /// Adds a folder at the end, with the feeds in it.
    @discardableResult
    func addFolder(named name: String, moving feedIDs: Set<Feed.ID> = []) throws(FolderNameError) -> Folder.ID {
        try change { library throws(FolderNameError) in
            let id = try library.addFolder(named: name)
            library.moveFeeds(feedIDs, to: id)
            return id
        }
    }

    func renameFolder(_ id: Folder.ID, to name: String) throws(FolderNameError) {
        try change { library throws(FolderNameError) in try library.renameFolder(id, to: name) }
    }

    /// Removes the folder; its feeds stay, in no folder.
    func removeFolder(_ id: Folder.ID) {
        update { $0.removeFolder(id) }
    }

    /// Moves the feeds into the folder, or out of any for `nil`.
    func moveFeeds(_ ids: some Sequence<Feed.ID>, to folder: Folder.ID?) {
        update { $0.moveFeeds(ids, to: folder) }
    }

    /// Moves the folder up (negative) or down in the sidebar.
    func moveFolder(_ id: Folder.ID, by offset: Int) {
        update { $0.moveFolder(id, by: offset) }
    }

    /// Drops a dragged feed or folder of the sidebar onto another item (`SidebarDrag.drop`).
    @discardableResult
    func drop(_ item: SidebarSelection, onto target: SidebarSelection) -> Bool {
        change { SidebarDrag.drop(item, onto: target, in: &$0) }
    }

    // MARK: Source pages

    /// P: loads the text of the article's source page unless it is stored.
    func loadPage(_ id: Article.ID) {
        pageQueue?.loadPage(id)
    }

    /// T: summarizes the article's source page, loading it first unless its text is stored.
    func summarizePage(_ id: Article.ID) {
        pageQueue?.summarize(id)
    }

    /// Whether T does anything for the article (`PageSummaryQueue.canSummarize`).
    func canSummarizePage(_ id: Article.ID) -> Bool {
        pageQueue?.canSummarize(id) ?? false
    }

    /// The user opened the article's source page in the window (`PageSummaryQueue.pageOpened`).
    func pageOpened(_ id: Article.ID) {
        pageQueue?.pageOpened(id)
    }

    // MARK: Changes

    func markRead(_ ids: [Article.ID]) {
        changeReadState(of: ids) { $0.markRead(ids, at: .now) }
    }

    func markUnread(_ ids: [Article.ID]) {
        changeReadState(of: ids) { $0.markUnread(ids) }
    }

    /// Patches the cached entries instead of building them again (reading with J/K changes the read state on every
    /// key). Read state never moves articles into stories, so the reader isn't told.
    private func changeReadState(of ids: [Article.ID], _ change: (inout Library) -> Void) {
        guard !ids.isEmpty else { return }
        let cache = entriesCache
        apply(change, notifiesReader: false)
        if var cache {
            cache.updateReadState(of: ids, library: library)
            entriesCache = cache
        }
    }

    /// Changes the library and saves it.
    func update(_ change: (inout Library) -> Void) {
        apply(change, notifiesReader: true)
    }

    /// Changes the library and saves it, unless the change fails; returns what the change returns.
    private func change<Result, Failure: Error>(
        _ change: (inout Library) throws(Failure) -> Result
    ) throws(Failure) -> Result {
        var library = library
        let result = try change(&library)
        update { $0 = library }
        return result
    }

    private func apply(_ change: (inout Library) -> Void, notifiesReader: Bool) {
        var library = library
        change(&library)
        guard library != self.library else { return }
        self.library = library
        if notifiesReader {
            onLibraryChange?()
        }
        saving = Task { [store, previous = saving] in
            await previous?.value
            await store.save(library)
        }
    }
}

/// The list entries for one summary language and choice of single-article summaries, with what is derived from
/// them.
private struct EntriesCache {
    let language: String
    let singleArticles: SingleArticleSummaries
    private(set) var entries: [StoryEntry]
    /// Positions in `entries`; reading doesn't change the order.
    let index: [StoryEntry.ID: Int]
    /// The folder of every feed in one, for the folder counts.
    private(set) var folders: [Feed.ID: Folder.ID]
    private(set) var counts: StoryList.Counts

    init(
        entries: [StoryEntry], folders: [Feed.ID: Folder.ID], language: String, singleArticles: SingleArticleSummaries
    ) {
        self.language = language
        self.singleArticles = singleArticles
        self.entries = entries
        self.folders = folders
        index = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        counts = StoryList.unreadCounts(entries, folders: folders)
    }

    mutating func updateReadState(of ids: [Article.ID], library: Library) {
        StoryList.updateReadState(of: ids, in: &entries, library: library)
        counts = StoryList.unreadCounts(entries, folders: folders)
    }

    mutating func setFolders(_ folders: [Feed.ID: Folder.ID]) {
        guard folders != self.folders else { return }
        self.folders = folders
        counts = StoryList.unreadCounts(entries, folders: folders)
    }
}
