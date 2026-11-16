import Foundation

extension Library {
    /// Saves the article at the date (S), or removes it from the saved ones for `nil`. Only articles are saved; a story
    /// is never saved as a whole.
    mutating func setSaved(_ id: Article.ID, at date: Date?) {
        articles[id]?.savedAt = date
    }

    /// The articles saving keeps: the saved ones.
    func articleIDsKeptBySaving() -> Set<Article.ID> {
        Set(articles.values.lazy.filter(\.isSaved).map(\.id))
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

    /// The name of the article's source: its feed's (`sourceTitle(of:)` of its feed ID), or a saved link's site.
    func sourceTitle(of article: Article) -> String? {
        article.isSavedLink ? article.site : sourceTitle(of: article.feedID)
    }

    /// The name of every feed articles can come from (`sourceTitle(of:)`).
    func sourceTitles() -> [Feed.ID: String] {
        removedFeeds.merging(feeds.map { ($0.id, $0.title) }) { _, current in current }
    }
}
