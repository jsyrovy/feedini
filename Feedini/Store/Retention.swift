import Foundation

/// What the library forgets and when.
///
/// - Unread articles are kept forever.
/// - Read articles go once their story (or the article itself, without a story) has had no article younger than
///   `attachWindow`: until then a new article about the same event can still join the known story. A removed article
///   leaves a tombstone, so the next refresh doesn't bring it back, and its page text goes with it.
/// - A tombstone goes once its article has been missing from the feed for `tombstoneMargin`, judged by the feed's
///   last successful download (a feed that can't be downloaded keeps its tombstones).
/// - Saved articles and stories are kept forever, and so is a story with a saved article (with all its articles).
/// - Articles of removed feeds that saving doesn't keep go (without a tombstone: the feed is gone), and so do the names
///   of removed feeds no article comes from.
/// - A topic goes once no story belongs to it.
enum Retention {
    static let attachWindow: TimeInterval = 72 * 60 * 60
    static let tombstoneMargin: TimeInterval = 3 * 24 * 60 * 60

    static func prune(_ library: inout Library, now: Date) {
        let cutoff = now.addingTimeInterval(-attachWindow)
        var removed = Set<Article.ID>()

        for story in library.stories.values {
            let articles = library.articles(of: story)
            if !story.isKeptBySaving(articles), articles.allSatisfy({ $0.isRead && $0.date < cutoff }) {
                removed.formUnion(articles.map(\.id))
            }
        }
        let storyIDs = library.storyIDsByArticle()
        for article in library.articles.values
        where storyIDs[article.id] == nil && article.isRead && !article.isSaved && article.date < cutoff {
            removed.insert(article.id)
        }
        let feedIDs = Set(library.feeds.map(\.id))
        let saved = library.articleIDsKeptBySaving()
        for article in library.articles.values where !feedIDs.contains(article.feedID) && !saved.contains(article.id) {
            removed.insert(article.id)
        }

        for id in removed {
            guard let article = library.articles[id], feedIDs.contains(article.feedID) else {
                continue
            }
            let key = article.tombstoneKey
            let lastSeen = max(library.tombstones[key]?.lastSeen ?? now, now)
            library.tombstones[key] = Tombstone(feedID: article.feedID, key: article.key, lastSeen: lastSeen)
        }
        library.removeArticles(removed)
        // Stories whose articles are all gone (none of them can be loaded) are removed too.
        let articles = library.articles
        remove(from: &library.stories) { _, story in !story.articleIDs.contains { articles[$0] != nil } }

        let lastSuccess = Dictionary(
            library.feeds.compactMap { feed in feed.lastSuccess.map { (feed.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        remove(from: &library.tombstones) { _, tombstone in
            guard let success = lastSuccess[tombstone.feedID] else { return false }
            return tombstone.lastSeen < success.addingTimeInterval(-tombstoneMargin)
        }

        let usedTopics = Set(library.stories.values.compactMap(\.topicID))
        remove(from: &library.topics) { id, _ in !usedTopics.contains(id) }

        let sources = Set(library.articles.values.map(\.feedID))
        remove(from: &library.removedFeeds) { id, _ in !sources.contains(id) }
    }

    /// Removes the matching entries in place: a dictionary with nothing to remove keeps its storage, so comparing
    /// the library before and after stays cheap.
    private static func remove<Key, Value>(
        from dictionary: inout [Key: Value], where shouldRemove: (Key, Value) -> Bool
    ) {
        for (key, value) in dictionary where shouldRemove(key, value) {
            dictionary[key] = nil
        }
    }
}
