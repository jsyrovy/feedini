import Foundation

/// What the sidebar selects.
enum SidebarSelection: Hashable, Sendable {
    case all
    case topic(Topic.ID)
    case feed(Feed.ID)
}

/// One item of the story list: a story, or an article no story holds yet (shown like a story with one article).
struct StoryEntry: Identifiable, Equatable, Sendable {
    enum ID: Hashable, Sendable {
        case story(Story.ID)
        /// An article without a story.
        case loose(Article.ID)
    }

    var id: ID
    var title: String
    var topicID: Topic.ID?
    /// Newest first.
    var articles: [Article]
    /// Articles that joined after the story had been read ("+1 new").
    var newArticleIDs: Set<Article.ID>
    /// Whether the story gets an AI summary in the summary language (several articles, or another language).
    var needsSummary = false
    /// The summary to show (`nil` when there is none or the story doesn't need one); it may be out of date.
    var summary: Summary?
    /// The summary covers exactly these articles in the summary language.
    var isSummaryCurrent = false

    /// The date of the newest article.
    var date: Date { articles.first?.date ?? .distantPast }
    var isRead: Bool { articles.allSatisfy(\.isRead) }
    var unreadCount: Int { articles.count { !$0.isRead } }
    /// A story with several articles; it can be expanded and has no single source page.
    var isMultiArticle: Bool { articles.count > 1 }

    /// The feeds of the articles, in the order of the articles, each once.
    var feedIDs: [Feed.ID] {
        var seen = Set<Feed.ID>()
        return articles.map(\.feedID).filter { seen.insert($0).inserted }
    }

    func article(_ id: Article.ID) -> Article? {
        articles.first { $0.id == id }
    }
}

/// Builds the story list and the sidebar counts from the library (pure).
enum StoryList {
    /// Every story and loose article, newest first (ties: by title). With a summary language, a story that needs
    /// a summary takes its title from it.
    static func allEntries(in library: Library, summaryLanguage: String? = nil) -> [StoryEntry] {
        var entries: [StoryEntry] = []
        var inStories = Set<Article.ID>()
        for story in library.stories.values {
            let articles = story.articleIDs.compactMap { library.articles[$0] }
            guard !articles.isEmpty else { continue }
            inStories.formUnion(story.articleIDs)
            let needsSummary = summaryLanguage.map { SummaryStep.needsSummary(articles, language: $0) } ?? false
            let summary = needsSummary ? story.summary : nil
            let title = summary?.title ?? (articles.count == 1 ? articles[0].title : story.title)
            entries.append(
                StoryEntry(
                    id: .story(story.id), title: title, topicID: story.topicID, articles: newestFirst(articles),
                    newArticleIDs: story.newArticleIDs, needsSummary: needsSummary, summary: summary,
                    isSummaryCurrent: summaryLanguage.map { SummaryStep.isCurrent(summary, of: story, language: $0) }
                        ?? false))
        }
        for article in library.articles.values where !inStories.contains(article.id) {
            entries.append(
                StoryEntry(
                    id: .loose(article.id), title: article.title, topicID: nil, articles: [article], newArticleIDs: []))
        }
        return entries.sorted { lhs, rhs in
            lhs.date != rhs.date
                ? lhs.date > rhs.date : lhs.title.localizedStandardCompare(rhs.title) == .orderedAscending
        }
    }

    /// The entries shown for a sidebar selection: unread ones, plus those in `keeping` (read while the list was
    /// shown, so they don't vanish under the cursor).
    static func entries(
        _ all: [StoryEntry], matching selection: SidebarSelection, keeping: Set<StoryEntry.ID> = []
    ) -> [StoryEntry] {
        all.filter { entry in
            (!entry.isRead || keeping.contains(entry.id)) && matches(entry, selection)
        }
    }

    static func matches(_ entry: StoryEntry, _ selection: SidebarSelection) -> Bool {
        switch selection {
        case .all: true
        case .topic(let id): entry.topicID == id
        case .feed(let id): entry.articles.contains { $0.feedID == id }
        }
    }

    struct Counts: Equatable, Sendable {
        var all = 0
        var topics: [Topic.ID: Int] = [:]
        var feeds: [Feed.ID: Int] = [:]

        func count(for selection: SidebarSelection) -> Int {
            switch selection {
            case .all: all
            case .topic(let id): topics[id, default: 0]
            case .feed(let id): feeds[id, default: 0]
            }
        }
    }

    /// Unread entries per sidebar item, matching what `entries` shows: a story counts once in every feed it has an
    /// article of.
    static func unreadCounts(_ all: [StoryEntry]) -> Counts {
        var counts = Counts()
        for entry in all where !entry.isRead {
            counts.all += 1
            if let topic = entry.topicID {
                counts.topics[topic, default: 0] += 1
            }
            for feed in entry.feedIDs {
                counts.feeds[feed, default: 0] += 1
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
