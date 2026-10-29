import Foundation

/// What the library forgets and when.
///
/// - Unread articles are kept forever.
/// - Read articles go once their story (or the article itself, without a story) has had no article younger than
///   `attachWindow`: until then a new article about the same event can still join the known story. A removed article
///   leaves a tombstone, so the next refresh doesn't bring it back.
/// - A tombstone goes once its article has been missing from the feed for `tombstoneMargin`, judged by the feed's
///   last successful download (a feed that can't be downloaded keeps its tombstones).
/// - A topic goes once no story belongs to it.
enum Retention {
    static let attachWindow: TimeInterval = 72 * 60 * 60
    static let tombstoneMargin: TimeInterval = 3 * 24 * 60 * 60

    static func prune(_ library: inout Library, now: Date) {
        let cutoff = now.addingTimeInterval(-attachWindow)
        var removed = Set<Article.ID>()

        for story in library.stories.values {
            let articles = story.articleIDs.compactMap { library.articles[$0] }
            let isStale = articles.allSatisfy(\.isRead) && articles.allSatisfy { $0.date < cutoff }
            if isStale {
                removed.formUnion(articles.map(\.id))
            }
        }
        let storyIDs = library.storyIDsByArticle()
        for article in library.articles.values
        where storyIDs[article.id] == nil && article.isRead && article.date < cutoff {
            removed.insert(article.id)
        }

        for id in removed {
            guard let article = library.articles.removeValue(forKey: id) else { continue }
            let key = article.tombstoneKey
            let lastSeen = max(library.tombstones[key]?.lastSeen ?? now, now)
            library.tombstones[key] = Tombstone(feedID: article.feedID, key: article.key, lastSeen: lastSeen)
        }
        library.removeFromStories(removed)
        // Stories whose articles are all gone (none of them can be loaded) are removed too.
        library.stories = library.stories.filter { _, story in
            story.articleIDs.contains { library.articles[$0] != nil }
        }

        let lastSuccess = Dictionary(
            library.feeds.compactMap { feed in feed.lastSuccess.map { (feed.id, $0) } },
            uniquingKeysWith: { first, _ in first })
        library.tombstones = library.tombstones.filter { _, tombstone in
            guard let success = lastSuccess[tombstone.feedID] else { return true }
            return tombstone.lastSeen >= success.addingTimeInterval(-tombstoneMargin)
        }

        let usedTopics = Set(library.stories.values.compactMap(\.topicID))
        library.topics = library.topics.filter { usedTopics.contains($0.key) }
    }
}
