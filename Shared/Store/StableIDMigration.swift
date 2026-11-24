import Foundation

/// Schema 3 (pure): feed and article IDs derived from the feed's address and the article's key (`StableID`) instead
/// of random ones, with every reference to them rewritten. Feeds of removed feeds keep their IDs (they have no
/// address any more), and so do folders, stories and topics.
enum StableIDMigration {
    /// Returns the new ID of every article whose ID changed (for the files of their page texts).
    static func migrate(_ library: inout Library) -> [Article.ID: Article.ID] {
        let feedIDs = migrateFeeds(&library)
        let articleIDs = migrateArticles(&library, feedIDs: feedIDs)
        for (id, var story) in library.stories {
            story.articleIDs = unique(story.articleIDs.map { articleIDs[$0] ?? $0 })
            if var summary = story.summary {
                summary.articleIDs = unique(summary.articleIDs.map { articleIDs[$0] ?? $0 })
                story.summary = summary
            }
            library.stories[id] = story
        }
        // Of tombstones that become one (merged feeds) the one seen last stays.
        var tombstones: [Tombstone.Key: Tombstone] = [:]
        for var tombstone in library.tombstones.values.sorted(by: { $0.lastSeen > $1.lastSeen }) {
            tombstone.feedID = feedIDs[tombstone.feedID] ?? tombstone.feedID
            let key = Tombstone.Key(feedID: tombstone.feedID, key: tombstone.key)
            if tombstones[key] == nil {
                tombstones[key] = tombstone
            }
        }
        library.tombstones = tombstones
        library.pageTextIDs = Set(library.pageTextIDs.map { articleIDs[$0] ?? $0 })
        return articleIDs.filter { $0.key != $0.value }
    }

    /// A second feed with the same address (adding one prevents that) merges into the first.
    private static func migrateFeeds(_ library: inout Library) -> [Feed.ID: Feed.ID] {
        var feedIDs: [Feed.ID: Feed.ID] = [:]
        var feeds: [Feed] = []
        for var feed in library.feeds {
            let id = StableID.feed(url: feed.url)
            feedIDs[feed.id] = id
            guard !feeds.contains(where: { $0.id == id }) else { continue }
            feed.id = id
            feeds.append(feed)
        }
        library.feeds = feeds
        return feedIDs
    }

    /// Articles that end up with the same ID (the same key in merged feeds) become one (`Article.merge`).
    private static func migrateArticles(
        _ library: inout Library, feedIDs: [Feed.ID: Feed.ID]
    ) -> [Article.ID: Article.ID] {
        var articleIDs: [Article.ID: Article.ID] = [:]
        var articles: [Article.ID: Article] = [:]
        let ordered = library.articles.values.sorted {
            ($0.firstSeen, $0.id.uuidString) < ($1.firstSeen, $1.id.uuidString)
        }
        for var article in ordered {
            article.feedID = feedIDs[article.feedID] ?? article.feedID
            let id = StableID.article(feed: article.feedID, key: article.key)
            articleIDs[article.id] = id
            article.id = id
            if var first = articles[id] {
                first.merge(article)
                articles[id] = first
            } else {
                articles[id] = article
            }
        }
        library.articles = articles
        return articleIDs
    }

    private static func unique(_ ids: [Article.ID]) -> [Article.ID] {
        var seen = Set<Article.ID>()
        return ids.filter { seen.insert($0).inserted }
    }
}
