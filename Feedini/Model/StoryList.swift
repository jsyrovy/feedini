import Foundation

/// What the sidebar selects.
enum SidebarSelection: Hashable, Sendable {
    case all
    /// The saved stories and articles (S).
    case saved
    case topic(Topic.ID)
    case folder(Folder.ID)
    case feed(Feed.ID)
}

extension Library {
    /// Whether the sidebar item still exists.
    func contains(_ selection: SidebarSelection) -> Bool {
        switch selection {
        case .all, .saved: true
        case .topic(let id): topics[id] != nil
        case .folder(let id): folder(id) != nil
        case .feed(let id): feed(id) != nil
        }
    }
}

/// The order of the story list (and Saved), remembered in `Preferences`.
enum ListOrder: String, CaseIterable, Sendable {
    /// By the newest article (Saved: the save date), newest first.
    case newestFirst
    case oldestFirst
}

/// One item of the story list: a story, or an article no story holds yet (shown like a story with one article).
struct StoryEntry: Identifiable, Equatable, Sendable {
    enum ID: Hashable, Sendable {
        case story(Story.ID)
        /// An article without a story.
        case loose(Article.ID)
        /// A saved article in Saved, shown on its own whether it belongs to a story or not.
        case savedArticle(Article.ID)
    }

    var id: ID
    var title: String
    var topicID: Topic.ID?
    /// Newest first.
    var articles: [Article]
    /// Articles that joined after the story had been read ("+1 new").
    var newArticleIDs: Set<Article.ID>
    /// Whether the story gets an AI summary in the summary language (`SummaryStep.needsSummary`).
    var needsSummary = false
    /// The summary to show (`nil` when there is none or the story doesn't need one); it may be out of date.
    var summary: Summary?
    /// The summary covers exactly these articles in the summary language.
    var isSummaryCurrent = false
    /// When the story was saved as a whole (S).
    var storySavedAt: Date?
    /// The list title of the story with several articles a saved article belongs to (in Saved).
    var partOf: String?

    /// The date of the newest article.
    var date: Date { articles.first?.date ?? .distantPast }
    var isRead: Bool { articles.allSatisfy(\.isRead) }
    var unreadCount: Int { articles.count { !$0.isRead } }
    /// A story with several articles; it can be expanded and has no single source page.
    var isMultiArticle: Bool { articles.count > 1 }
    /// A saved link (`SavedLink`): shown in Saved only.
    var isSavedLink: Bool { articles.contains(where: \.isSavedLink) }

    /// The first article of every feed, in the order of the articles: one per source (`Library.sourceTitle(of:)`).
    var sourceArticles: [Article] {
        var seen = Set<Feed.ID>()
        return articles.filter { seen.insert($0.feedID).inserted }
    }

    /// The feeds of the articles, in the order of the articles, each once.
    var feedIDs: [Feed.ID] { sourceArticles.map(\.feedID) }

    func article(_ id: Article.ID) -> Article? {
        articles.first { $0.id == id }
    }

    /// What S saves on the row: an article row its article; the story row the story when it has several articles
    /// (or was saved as a whole), else its article.
    func savedItem(at row: ListRow) -> SavedItem? {
        switch row {
        case .article(_, let id):
            return .article(id)
        case .story:
            if case .story(let id) = id, isMultiArticle || storySavedAt != nil {
                return .story(id)
            }
            return articles.first.map { .article($0.id) }
        }
    }

    /// When the item the row stands for was saved; `nil` when it isn't saved.
    func savedAt(at row: ListRow) -> Date? {
        switch savedItem(at: row) {
        case .story: storySavedAt
        case .article(let id): article(id)?.savedAt
        case nil: nil
        }
    }

    /// The article P, T and Shift+S work on: the article of an article row, the only article of a story row; none for
    /// the row of a story with several articles.
    func singleArticle(at row: ListRow) -> Article? {
        if case .story = row, isMultiArticle {
            return nil
        }
        return article(at: row)
    }

    /// The article a row stands for: the article of an article row, the newest one for the story row.
    func article(at row: ListRow) -> Article? {
        switch row {
        case .story: articles.first
        case .article(_, let id): article(id)
        }
    }
}

/// Builds the story list and the sidebar counts from the library (pure).
enum StoryList {
    /// Every story and loose article, newest first (ties: by title). A story that needs a summary takes its title
    /// from it.
    static func allEntries(
        in library: Library, summaryLanguage: String, singleArticles: SingleArticleSummaries
    ) -> [StoryEntry] {
        var entries: [StoryEntry] = []
        var inStories = Set<Article.ID>()
        for story in library.stories.values {
            guard
                let entry = entry(
                    for: story, in: library, summaryLanguage: summaryLanguage, singleArticles: singleArticles)
            else { continue }
            inStories.formUnion(story.articleIDs)
            entries.append(entry)
        }
        for article in library.articles.values where !inStories.contains(article.id) {
            entries.append(entry(for: article))
        }
        return sorted(entries.map { ($0.date, $0) })
    }

    /// Newest first (ties: by title).
    private static func sorted(_ dated: [(date: Date, entry: StoryEntry)]) -> [StoryEntry] {
        dated.sorted { lhs, rhs in
            lhs.date != rhs.date
                ? lhs.date > rhs.date : lhs.entry.title.localizedStandardCompare(rhs.entry.title) == .orderedAscending
        }.map(\.entry)
    }

    /// The entry of a story; `nil` when none of its articles exists.
    static func entry(
        for story: Story, in library: Library, summaryLanguage: String, singleArticles: SingleArticleSummaries
    ) -> StoryEntry? {
        let articles = library.articles(of: story)
        guard !articles.isEmpty else { return nil }
        let needsSummary = SummaryStep.needsSummary(
            articles, language: summaryLanguage, singleArticles: singleArticles)
        let summary = needsSummary ? story.summary : nil
        let title = summary?.title ?? (articles.count == 1 ? articles[0].title : story.title)
        return StoryEntry(
            id: .story(story.id), title: title, topicID: story.topicID, articles: newestFirst(articles),
            newArticleIDs: story.newArticleIDs, needsSummary: needsSummary, summary: summary,
            isSummaryCurrent: SummaryStep.isCurrent(summary, of: story, language: summaryLanguage),
            storySavedAt: story.savedAt)
    }

    /// The entry of an article no story holds.
    static func entry(for article: Article) -> StoryEntry {
        StoryEntry(id: .loose(article.id), title: article.title, topicID: nil, articles: [article], newArticleIDs: [])
    }

    /// The saved stories and articles, most recently saved first (ties: by title): a saved story as its entry, a saved
    /// article as `savedEntry`. `entry` gives the entries of `allEntries` by ID, `storyIDs` the story of every article
    /// in one (`Library.storyIDsByArticle`).
    static func savedEntries(
        in library: Library, storyIDs: [Article.ID: Story.ID], entry: (StoryEntry.ID) -> StoryEntry?
    ) -> [StoryEntry] {
        var dated: [(date: Date, entry: StoryEntry)] = []
        for story in library.stories.values {
            if let date = story.savedAt, let entry = entry(.story(story.id)) {
                dated.append((date, entry))
            }
        }
        for article in library.articles.values {
            if let date = article.savedAt {
                let container = storyIDs[article.id].map { entry(.story($0)) } ?? entry(.loose(article.id))
                dated.append((date, savedEntry(for: article, in: container)))
            }
        }
        return sorted(dated)
    }

    /// Saved with entries removed from it while it was shown, each at the place its former save date gives it.
    static func savedEntries(_ saved: [StoryEntry], keeping kept: [(date: Date, entry: StoryEntry)]) -> [StoryEntry] {
        guard !kept.isEmpty else { return saved }
        return sorted(saved.map { ($0.savedAt(at: .story($0.id)) ?? .distantPast, $0) } + kept)
    }

    /// A saved article on its own (`.savedArticle`), with the title of its story when that has several articles, or
    /// with the summary of its one-article story. `container` is the entry of its story, or its loose entry.
    static func savedEntry(for article: Article, in container: StoryEntry?) -> StoryEntry {
        var entry = StoryEntry(
            id: .savedArticle(article.id), title: article.title, topicID: container?.topicID, articles: [article],
            newArticleIDs: [])
        if let container, container.isMultiArticle {
            entry.partOf = container.title
        } else if let container, case .story = container.id {
            entry.title = container.title
            entry.needsSummary = container.needsSummary
            entry.summary = container.summary
            entry.isSummaryCurrent = container.isSummaryCurrent
        }
        return entry
    }

    /// Updates the entries holding the articles, and those of the stories, after their reading state (read and save
    /// dates, "new" marks) changed – which changes neither the order nor the grouping – instead of building all entries
    /// again (reading with J/K changes it on every key). Returns whether the saving of an entry changed.
    @discardableResult
    static func updateReadingState(
        of articleIDs: some Sequence<Article.ID>, stories storyIDs: some Sequence<Story.ID> = [Story.ID](),
        in entries: inout [StoryEntry], library: Library
    ) -> Bool {
        let wanted = Set(articleIDs)
        let wantedStories = Set(storyIDs)
        var savingChanged = false
        for index in entries.indices {
            let storyID: Story.ID? = if case .story(let id) = entries[index].id { id } else { nil }
            guard
                storyID.map(wantedStories.contains) == true
                    || entries[index].articles.contains(where: { wanted.contains($0.id) })
            else { continue }
            for position in entries[index].articles.indices {
                if let article = library.articles[entries[index].articles[position].id] {
                    savingChanged = savingChanged || entries[index].articles[position].savedAt != article.savedAt
                    entries[index].articles[position].readAt = article.readAt
                    entries[index].articles[position].savedAt = article.savedAt
                }
            }
            if let storyID, let story = library.stories[storyID] {
                savingChanged = savingChanged || entries[index].storySavedAt != story.savedAt
                entries[index].newArticleIDs = story.newArticleIDs
                entries[index].storySavedAt = story.savedAt
            }
        }
        return savingChanged
    }

    /// The entries, built newest first, in the order. Oldest first is the same list read from the other end; the
    /// articles inside a story stay newest first.
    static func ordered(_ entries: [StoryEntry], _ order: ListOrder) -> [StoryEntry] {
        switch order {
        case .newestFirst: entries
        case .oldestFirst: entries.reversed()
        }
    }

    /// The entries shown for a sidebar selection: unread ones, plus those in `keeping` (read while the list was
    /// shown, so they don't vanish under the cursor). `folders` is the folder of every feed in one
    /// (`Library.folderIDsByFeed`).
    static func entries(
        _ all: [StoryEntry], matching selection: SidebarSelection, folders: [Feed.ID: Folder.ID],
        keeping: Set<StoryEntry.ID> = []
    ) -> [StoryEntry] {
        all.filter { entry in
            (!entry.isRead || keeping.contains(entry.id)) && matches(entry, selection, folders: folders)
        }
    }

    /// A folder shows every story with an article of one of its feeds.
    static func matches(
        _ entry: StoryEntry, _ selection: SidebarSelection, folders: [Feed.ID: Folder.ID]
    ) -> Bool {
        switch selection {
        // Saved links are in Saved only.
        case .all: !entry.isSavedLink
        // Saved has its own entries (`savedEntries`).
        case .saved: false
        case .topic(let id): entry.topicID == id
        case .folder(let id): entry.articles.contains { folders[$0.feedID] == id }
        case .feed(let id): entry.articles.contains { $0.feedID == id }
        }
    }

    struct Counts: Equatable, Sendable {
        var all = 0
        /// Every saved entry, read or not.
        var saved = 0
        var topics: [Topic.ID: Int] = [:]
        var folders: [Folder.ID: Int] = [:]
        var feeds: [Feed.ID: Int] = [:]

        func count(for selection: SidebarSelection) -> Int {
            switch selection {
            case .all: all
            case .saved: saved
            case .topic(let id): topics[id, default: 0]
            case .folder(let id): folders[id, default: 0]
            case .feed(let id): feeds[id, default: 0]
            }
        }
    }

    /// Unread entries per sidebar item, matching what `entries` shows: a story counts once in every feed it has an
    /// article of, and once in every folder of those feeds (not once per feed). Saved is left to the caller; saved
    /// links count nowhere else.
    static func unreadCounts(_ all: [StoryEntry], folders: [Feed.ID: Folder.ID]) -> Counts {
        var counts = Counts()
        for entry in all where !entry.isRead && !entry.isSavedLink {
            counts.all += 1
            if let topic = entry.topicID {
                counts.topics[topic, default: 0] += 1
            }
            var countedFolders: [Folder.ID] = []
            for feed in entry.feedIDs {
                counts.feeds[feed, default: 0] += 1
                if let folder = folders[feed], !countedFolders.contains(folder) {
                    countedFolders.append(folder)
                    counts.folders[folder, default: 0] += 1
                }
            }
        }
        return counts
    }

    /// Topics with unread stories, most unread first (ties: by name).
    static func topics(in library: Library, counts: Counts) -> [Topic] {
        library.topics.values.filter { counts.topics[$0.id, default: 0] > 0 }.sorted { lhs, rhs in
            let (left, right) = (counts.topics[lhs.id, default: 0], counts.topics[rhs.id, default: 0])
            return left != right ? left > right : lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }

    private static func newestFirst(_ articles: [Article]) -> [Article] {
        articles.sorted { $0.date != $1.date ? $0.date > $1.date : $0.title < $1.title }
    }
}
