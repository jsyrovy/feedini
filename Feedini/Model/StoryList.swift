import Foundation

/// What the sidebar selects.
enum SidebarSelection: Hashable, Sendable {
    case all
    /// The saved articles (S).
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
///
/// A story shows only some of its articles (`visible(keeping:)`): the unread ones and those read while the list is
/// shown. Its title, summary and everything else (the number of articles, sources, expanding, keys) follow them; with
/// one article shown it behaves like an article.
struct StoryEntry: Identifiable, Equatable, Sendable {
    enum ID: Hashable, Sendable {
        case story(Story.ID)
        /// An article without a story.
        case loose(Article.ID)
        /// A saved article in Saved, shown on its own whether it belongs to a story or not.
        case savedArticle(Article.ID)
    }

    /// What the entry of a story is built from, to show some of its articles (`show(_:)`).
    struct StoryInfo: Equatable, Sendable {
        /// The story's own (AI) title: the title of several articles without a summary.
        var title: String
        /// The story's stored summary; it may be out of date.
        var summary: Summary?
        var summaryLanguage: String
        var singleArticles: SingleArticleSummaries
    }

    var id: ID
    var title: String
    var topicID: Topic.ID?
    /// The articles shown, newest first.
    var articles: [Article]
    /// Whether the articles get an AI summary in the summary language (`SummaryStep.needsSummary`).
    var needsSummary = false
    /// The summary to show (`nil` when there is none or the articles don't need one); it may be out of date.
    var summary: Summary?
    /// The summary is in the summary language and covers every unread article.
    var isSummaryCurrent = false
    /// `nil` for an article without a story and a saved article.
    var story: StoryInfo?

    /// The date of the newest article.
    var date: Date { articles.first?.date ?? .distantPast }
    var isRead: Bool { articles.allSatisfy(\.isRead) }
    var unreadCount: Int { articles.count { !$0.isRead } }
    /// A story with several articles; it can be expanded and has no single source page.
    var isMultiArticle: Bool { articles.count > 1 }
    /// A saved link (`SavedLink`): shown in Saved only.
    var isSavedLink: Bool { articles.contains(where: \.isSavedLink) }
    /// Whether one of the articles is saved (the row has a bookmark).
    var containsSaved: Bool { articles.contains(where: \.isSaved) }

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

    /// Shows the articles (newest first): a story takes its title and summary from them – the summary when they need
    /// one, else the title of a single article or the story's own.
    mutating func show(_ articles: [Article]) {
        self.articles = articles
        guard let story else { return }
        needsSummary = SummaryStep.needsSummary(
            articles, language: story.summaryLanguage, singleArticles: story.singleArticles)
        summary = needsSummary ? story.summary : nil
        title = summary?.title ?? (articles.count == 1 ? articles[0].title : story.title)
        isSummaryCurrent = SummaryStep.isCurrent(summary, of: articles, language: story.summaryLanguage)
    }

    /// The entry with only the articles to show: unread ones and those in `keeping` (read while the list is shown);
    /// `nil` when none is left. A saved article in Saved shows read or not.
    func visible(keeping: Set<Article.ID>) -> StoryEntry? {
        if case .savedArticle = id {
            return self
        }
        let isShown = { (article: Article) in !article.isRead || keeping.contains(article.id) }
        // The usual cases (all unread, all read) without building anything.
        if articles.allSatisfy(isShown) {
            return articles.isEmpty ? nil : self
        }
        let shown = articles.filter(isShown)
        guard !shown.isEmpty else { return nil }
        var entry = self
        entry.show(shown)
        return entry
    }

    /// The article P, T, S and Shift+S work on: the article of an article row, the only article of a story row; none
    /// for the row of a story with several articles.
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

    /// The entry of a story with all its articles (`StoryEntry.visible(keeping:)` leaves out the read ones); `nil`
    /// when none of its articles exists.
    static func entry(
        for story: Story, in library: Library, summaryLanguage: String, singleArticles: SingleArticleSummaries
    ) -> StoryEntry? {
        let articles = library.articles(of: story)
        guard !articles.isEmpty else { return nil }
        var entry = StoryEntry(
            id: .story(story.id), title: story.title, topicID: story.topicID, articles: [],
            story: StoryEntry.StoryInfo(
                title: story.title, summary: story.summary, summaryLanguage: summaryLanguage,
                singleArticles: singleArticles))
        entry.show(newestFirst(articles))
        return entry
    }

    /// The entry of an article no story holds.
    static func entry(for article: Article) -> StoryEntry {
        StoryEntry(id: .loose(article.id), title: article.title, topicID: nil, articles: [article])
    }

    /// The saved articles, most recently saved first (ties: by title), each on its own (`savedEntry`).
    static func savedEntries(in library: Library) -> [StoryEntry] {
        sorted(library.articles.values.compactMap { article in article.savedAt.map { ($0, savedEntry(for: article)) } })
    }

    /// Saved with entries removed from it while it was shown, each at the place its former save date gives it.
    static func savedEntries(_ saved: [StoryEntry], keeping kept: [(date: Date, entry: StoryEntry)]) -> [StoryEntry] {
        guard !kept.isEmpty else { return saved }
        return sorted(saved.map { ($0.articles.first?.savedAt ?? .distantPast, $0) } + kept)
    }

    /// A saved article on its own (`.savedArticle`): its title and text, never its story's.
    static func savedEntry(for article: Article) -> StoryEntry {
        StoryEntry(id: .savedArticle(article.id), title: article.title, topicID: nil, articles: [article])
    }

    /// Updates the entries holding the articles after their reading state (read and save dates) changed – which
    /// changes neither the order nor the grouping – instead of building all entries again (reading with J/K changes it
    /// on every key). Returns whether the saving of an entry changed.
    @discardableResult
    static func updateReadingState(
        of articleIDs: some Sequence<Article.ID>, in entries: inout [StoryEntry], library: Library
    ) -> Bool {
        let wanted = Set(articleIDs)
        var savingChanged = false
        for index in entries.indices where entries[index].articles.contains(where: { wanted.contains($0.id) }) {
            var articles = entries[index].articles
            for position in articles.indices {
                if let article = library.articles[articles[position].id] {
                    savingChanged = savingChanged || articles[position].savedAt != article.savedAt
                    articles[position].readAt = article.readAt
                    articles[position].savedAt = article.savedAt
                }
            }
            // Whether the summary is current depends on the unread articles.
            entries[index].show(articles)
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

    /// The entries shown for a sidebar selection, with the articles they show: unread ones, plus those in `keeping`
    /// (read while the list was shown, so they don't vanish under the cursor). An entry without any isn't shown.
    /// `folders` is the folder of every feed in one (`Library.folderIDsByFeed`).
    static func entries(
        _ all: [StoryEntry], matching selection: SidebarSelection, folders: [Feed.ID: Folder.ID],
        keeping: Set<Article.ID> = []
    ) -> [StoryEntry] {
        all.compactMap { entry in
            entry.visible(keeping: keeping).flatMap { matches($0, selection, folders: folders) ? $0 : nil }
        }
    }

    /// A feed shows every story with an article of it, a folder every story with an article of one of its feeds
    /// (of the articles the entry shows).
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
        /// Every saved article, read or not.
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
    /// unread article of, and once in every folder of those feeds (not once per feed). Saved is left to the caller;
    /// saved links count nowhere else.
    static func unreadCounts(_ all: [StoryEntry], folders: [Feed.ID: Folder.ID]) -> Counts {
        var counts = Counts()
        for entry in all where !entry.isRead && !entry.isSavedLink {
            counts.all += 1
            if let topic = entry.topicID {
                counts.topics[topic, default: 0] += 1
            }
            // The feeds of the unread articles: those `visible(keeping: [])` shows.
            let feeds = Set(entry.articles.lazy.filter { !$0.isRead }.map(\.feedID))
            for feed in feeds {
                counts.feeds[feed, default: 0] += 1
            }
            for folder in Set(feeds.compactMap { folders[$0] }) {
                counts.folders[folder, default: 0] += 1
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
