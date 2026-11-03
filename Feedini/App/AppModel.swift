import Foundation
import Observation

/// Connects the layers: holds the library on the main actor, saves its changes, runs the refreshes.
@MainActor
@Observable
final class AppModel: LibraryHost {
    let preferences: Preferences
    let aiStatus = AIStatus()
    let backups: Backups
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
    /// Called after a backup replaced the library (the reader starts over).
    @ObservationIgnored var onRestore: (@MainActor () -> Void)?

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
        pageExtractor: (any PageExtracting)? = nil, backupStore: BackupStore = BackupStore()
    ) {
        self.preferences = preferences
        backups = Backups(store: backupStore, preferences: preferences)
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

    /// The saved stories and articles, most recently saved first, with entries removed from Saved while it was shown
    /// at the place of their former save date.
    func savedEntries(keeping: [StoryEntry.ID: Date] = [:]) -> [StoryEntry] {
        let cache = cache
        let kept = keeping.compactMap { id, date in
            cache.savedIndex[id] == nil ? entry(id).map { (date: date, entry: $0) } : nil
        }
        return StoryList.savedEntries(cache.saved, keeping: kept)
    }

    /// Unread entries per sidebar item.
    var unreadCounts: StoryList.Counts { cache.counts }

    /// The folder of every feed in one.
    var folderIDsByFeed: [Feed.ID: Folder.ID] { cache.folders }

    /// An entry of `entries` or Saved; a `.savedArticle` entry also for an article that isn't saved (anymore).
    func entry(_ id: StoryEntry.ID) -> StoryEntry? {
        let cache = cache
        guard case .savedArticle(let articleID) = id else { return cache.index[id].map { cache.entries[$0] } }
        if let position = cache.savedIndex[id] {
            return cache.saved[position]
        }
        return library.articles[articleID].map { StoryList.savedEntry(for: $0, in: cache.container(of: articleID)) }
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
            library: library, language: language, singleArticles: singleArticles)
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
        // Turning backups on backs up at once (the first one, or one that is due), so macOS asks for access to iCloud
        // Drive now and a problem shows right away.
        preferences.onBackupChange = { [weak self] in
            self?.backUpIfDue()
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
        backUpIfDue()
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

    // MARK: Backups

    /// An automatic backup if it is due. Not awaited: the refresh loop mustn't wait for iCloud Drive (or for the user
    /// to answer macOS asking for access to it).
    private func backUpIfDue() {
        Task { [weak self] in
            guard let self else { return }
            await backups.backUpIfDue { self.library }
        }
    }

    /// Whether Back Up Now does anything.
    var canBackUpNow: Bool {
        !backups.isBackingUp && !library.feeds.isEmpty
    }

    /// Back Up Now; a failure shows in `backups.problem`.
    func backUpNow() {
        Task { [backups, library] in try? await backups.backUp(library) }
    }

    /// Replaces the library with a backup's, and the settings too if asked. The current library is backed up first
    /// (unless it has no feeds, as on a new Mac: `Backups.backUp`); if that fails, nothing changes. Refreshing and the AI stop meanwhile
    /// and start again with the restored library; page texts stay for the articles that are in it.
    func restore(_ contents: BackupFile.Contents, settings: Bool) async throws(BackupError) {
        try await backups.backUp(library, kind: .beforeRestore)
        await scheduler?.stop()
        assignQueue?.cancel()
        summaryQueue?.cancel()
        await assignQueue?.waitUntilIdle()
        await summaryQueue?.waitUntilIdle()
        var restored = contents.library
        restored.pageTextIDs = library.pageTextIDs.filter { restored.articles[$0] != nil }
        update { $0 = restored }
        if settings {
            preferences.apply(contents.settings)
        }
        Log.store.info(
            "Restored a backup of \(contents.created, privacy: .public) from \(contents.device, privacy: .public)")
        onRestore?()
        scheduler?.start()
        organize(retryingFailed: true)
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

    // MARK: Saved links

    /// Save Link…: saves the page at the address (`Library.saveLink`) and loads it with its summary in the background,
    /// as Shift+S does (without AI only its text).
    @discardableResult
    func saveLink(_ address: String) throws(SavedLink.Failure) -> SavedLink.Outcome {
        let url = try SavedLink.url(from: address)
        let outcome = change { $0.saveLink(url, at: .now) }
        if case .saved(let id) = outcome {
            // Without AI only the text: every saved link would say that AI is off.
            if preferences.aiEnabled {
                pageQueue?.prepare(id)
            } else {
                pageQueue?.loadPage(id)
            }
        }
        return outcome
    }

    /// Links dropped on the window: saves every web address among them; returns whether any was saved.
    @discardableResult
    func saveLinks(_ urls: [URL]) -> Bool {
        var saved = false
        for address in urls.compactMap({ SavedLink.webAddress($0.absoluteString) }) {
            if (try? saveLink(address)) != nil {
                saved = true
            }
        }
        return saved
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

    /// Shift+S: loads and summarizes the article's source page, the page also without AI
    /// (`PageSummaryQueue.prepare`).
    func preparePage(_ id: Article.ID) {
        pageQueue?.prepare(id)
    }

    /// P on a saved link: loads its page again (`PageSummaryQueue.reload`).
    func reloadPage(_ id: Article.ID) {
        pageQueue?.reload(id)
    }

    /// Whether T does anything for the article (`PageSummaryQueue.canSummarize`).
    func canSummarizePage(_ id: Article.ID) -> Bool {
        pageQueue?.canSummarize(id) ?? false
    }

    /// The user opened the article's source page in the window (`PageSummaryQueue.pageOpened`).
    func pageOpened(_ id: Article.ID) {
        pageQueue?.pageOpened(id)
    }

    func pageText(_ id: Article.ID) async -> String? {
        guard library.pageTextIDs.contains(id) else { return nil }
        if let text = await store.pageText(for: id) {
            return text
        }
        // The file is gone: the next P / T loads the page again.
        update { $0.pageTextIDs.remove(id) }
        return nil
    }

    func storePageText(_ text: String, for id: Article.ID) async throws {
        try await store.storePageText(text, for: id)
        // Unless the article went away meanwhile; the store deletes the file when loading next time.
        guard library.articles[id] != nil else { return }
        update { $0.pageTextIDs.insert(id) }
    }

    // MARK: Changes

    /// Puts the reading state back (⌘Z); returns the state it replaced, `nil` when none of the items exists anymore.
    func restore(_ state: ReadingState) -> ReadingState? {
        var replaced = ReadingState()
        changeReadingState(of: Array(state.articles.keys), stories: Array(state.stories.keys)) {
            replaced = $0.restore(state)
        }
        return replaced.isEmpty ? nil : replaced
    }

    /// Saves the item for later (S), or removes it from Saved for `nil`.
    func setSaved(_ item: SavedItem, at date: Date?) {
        switch item {
        case .article(let id): changeReadingState(of: [id]) { $0.setSaved(item, at: date) }
        case .story(let id): changeReadingState(stories: [id]) { $0.setSaved(item, at: date) }
        }
    }

    func markRead(_ ids: [Article.ID]) {
        changeReadingState(of: ids) { $0.markRead(ids, at: .now) }
    }

    func markUnread(_ ids: [Article.ID]) {
        changeReadingState(of: ids) { $0.markUnread(ids) }
    }

    /// Patches the cached entries instead of building them again: reading (with J/K on every key) and saving change
    /// neither the order nor the grouping. Nor do they move articles into stories, so the reader isn't told.
    private func changeReadingState(
        of ids: [Article.ID] = [], stories: [Story.ID] = [], _ change: (inout Library) -> Void
    ) {
        guard !ids.isEmpty || !stories.isEmpty else { return }
        let cache = entriesCache
        apply(change, notifiesReader: false)
        if var cache {
            cache.updateReadingState(of: ids, stories: stories, library: library)
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
    /// The story of every article in one; reading and saving don't change it.
    let storyIDs: [Article.ID: Story.ID]
    /// The entries of Saved.
    private(set) var saved: [StoryEntry] = []
    /// Positions in `saved`.
    private(set) var savedIndex: [StoryEntry.ID: Int] = [:]
    /// The folder of every feed in one, for the folder counts.
    private(set) var folders: [Feed.ID: Folder.ID]
    private(set) var counts: StoryList.Counts

    init(entries: [StoryEntry], library: Library, language: String, singleArticles: SingleArticleSummaries) {
        self.language = language
        self.singleArticles = singleArticles
        self.entries = entries
        folders = library.folderIDsByFeed()
        index = Dictionary(uniqueKeysWithValues: entries.enumerated().map { ($1.id, $0) })
        storyIDs = library.storyIDsByArticle()
        counts = StoryList.Counts()
        buildSaved(library)
        recount()
    }

    /// The entry of the article's story, or its loose entry.
    func container(of articleID: Article.ID) -> StoryEntry? {
        let id: StoryEntry.ID = storyIDs[articleID].map { .story($0) } ?? .loose(articleID)
        return index[id].map { entries[$0] }
    }

    mutating func updateReadingState(of ids: [Article.ID], stories: [Story.ID], library: Library) {
        if StoryList.updateReadingState(of: ids, stories: stories, in: &entries, library: library) {
            buildSaved(library)
        } else {
            StoryList.updateReadingState(of: ids, in: &saved, library: library)
        }
        recount()
    }

    mutating func setFolders(_ folders: [Feed.ID: Folder.ID]) {
        guard folders != self.folders else { return }
        self.folders = folders
        recount()
    }

    private mutating func buildSaved(_ library: Library) {
        let (entries, index) = (entries, index)
        saved = StoryList.savedEntries(in: library, storyIDs: storyIDs) { id in index[id].map { entries[$0] } }
        savedIndex = Dictionary(uniqueKeysWithValues: saved.enumerated().map { ($1.id, $0) })
    }

    private mutating func recount() {
        counts = StoryList.unreadCounts(entries, folders: folders)
        counts.saved = saved.count
    }
}
