import Foundation
import Observation

/// Connects the layers: holds the library on the main actor, saves its changes, runs the refreshes.
@MainActor
@Observable
final class AppModel {
    let preferences: Preferences
    private(set) var library = Library() {
        didSet { cachedEntries = nil }
    }
    private(set) var isLoaded = false
    private(set) var isRefreshing = false
    private(set) var lastRefresh: Date?
    /// Why the saved library couldn't be used, if it couldn't.
    private(set) var loadProblem: String?

    /// Called after every refresh (the reader drops read entries from the list then).
    @ObservationIgnored var onRefresh: (@MainActor () -> Void)?

    @ObservationIgnored private let store: LibraryStore
    @ObservationIgnored private let coordinator: RefreshCoordinator
    @ObservationIgnored private var scheduler: RefreshScheduler?
    @ObservationIgnored private var cachedEntries: [StoryEntry]?
    /// The latest hand-over to the store; each waits for the previous one, so saves keep their order.
    @ObservationIgnored private var saving: Task<Void, Never>?

    init(
        preferences: Preferences = Preferences(), store: LibraryStore = LibraryStore(),
        coordinator: RefreshCoordinator = RefreshCoordinator()
    ) {
        self.preferences = preferences
        self.store = store
        self.coordinator = coordinator
    }

    /// All stories and loose articles, newest first.
    var entries: [StoryEntry] {
        let library = library
        if let cachedEntries {
            return cachedEntries
        }
        let entries = StoryList.allEntries(in: library)
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
        scheduler.start()
        self.scheduler = scheduler
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

    // MARK: Changes

    func markRead(_ ids: [Article.ID]) {
        guard !ids.isEmpty else { return }
        update { $0.markRead(ids, at: .now) }
    }

    func markUnread(_ ids: [Article.ID]) {
        guard !ids.isEmpty else { return }
        update { $0.markUnread(ids) }
    }

    /// Changes the library and saves it.
    func update(_ change: (inout Library) -> Void) {
        var library = library
        change(&library)
        guard library != self.library else { return }
        self.library = library
        saving = Task { [store, previous = saving] in
            await previous?.value
            await store.save(library)
        }
    }
}
