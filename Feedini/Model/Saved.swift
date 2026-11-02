import Foundation

/// What S saves for later: an article (also the one of a one-article story), or a story with several articles as a
/// whole.
enum SavedItem: Hashable, Sendable {
    case article(Article.ID)
    case story(Story.ID)
}

extension Story {
    /// Saved as a whole or holding a saved article (of `articles`, its articles): such a story is kept whole and its
    /// summary up to date, read or not.
    func isKeptBySaving(_ articles: [Article]) -> Bool {
        savedAt != nil || articles.contains(where: \.isSaved)
    }
}

extension Library {
    /// Saves the item at the date, or removes it from the saved ones for `nil`.
    mutating func setSaved(_ item: SavedItem, at date: Date?) {
        switch item {
        case .article(let id): articles[id]?.savedAt = date
        case .story(let id): stories[id]?.savedAt = date
        }
    }

    /// The articles saving keeps: saved articles, and every article of a saved story.
    func articleIDsKeptBySaving() -> Set<Article.ID> {
        var ids = Set(articles.values.lazy.filter(\.isSaved).map(\.id))
        for story in stories.values where story.savedAt != nil {
            ids.formUnion(story.articleIDs)
        }
        return ids
    }

    /// How many articles of the feeds saving keeps (they stay when the feeds are removed).
    func savedArticleCount(of feedIDs: Set<Feed.ID>) -> Int {
        articleIDsKeptBySaving().count { articles[$0].map { feedIDs.contains($0.feedID) } ?? false }
    }

    /// The name of the feed the article comes from, also when the feed has been removed and only saved articles
    /// remain.
    func sourceTitle(of feedID: Feed.ID) -> String? {
        feed(feedID)?.title ?? removedFeeds[feedID]
    }

    /// The name of every feed articles can come from (`sourceTitle(of:)`).
    func sourceTitles() -> [Feed.ID: String] {
        removedFeeds.merging(feeds.map { ($0.id, $0.title) }) { _, current in current }
    }
}
