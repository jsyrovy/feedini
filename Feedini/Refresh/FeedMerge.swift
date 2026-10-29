import Foundation

/// The result of refreshing one feed, before it is merged.
enum FeedRefresh: Sendable, Equatable {
    case updated(ParsedFeed, etag: String?, lastModified: String?)
    case notModified
    case failed(String)
}

/// Merges refreshed feeds into the library (pure).
///
/// - New items become unread articles; items already in the library are left alone (the feed may have edited them,
///   the reader keeps what it showed); items with a tombstone (read and removed) only refresh the tombstone.
/// - The first download of a feed skips items older than `firstDownloadMaxAge`: they become tombstones, so adding a
///   feed with years of history doesn't flood the list.
/// - A failed feed only records the error; everything it had stays.
enum FeedMerge {
    static let firstDownloadMaxAge: TimeInterval = 7 * 24 * 60 * 60

    /// Returns the IDs of the new articles.
    @discardableResult
    static func merge(_ refreshes: [Feed.ID: FeedRefresh], into library: inout Library, now: Date) -> [Article.ID] {
        var newArticles: [Article.ID] = []
        for index in library.feeds.indices {
            let feedID = library.feeds[index].id
            switch refreshes[feedID] {
            case nil:
                continue
            case .failed(let message):
                library.feeds[index].lastError = message
            case .notModified:
                library.feeds[index].lastChecked = now
                library.feeds[index].lastError = nil
            case .updated(let parsed, let etag, let lastModified):
                let isFirstDownload = library.feeds[index].lastSuccess == nil
                var feed = library.feeds[index]
                feed.etag = etag
                feed.lastModified = lastModified
                feed.lastSuccess = now
                feed.lastChecked = now
                feed.lastError = nil
                feed.language = FeedLanguage.code(parsed.language)
                feed.siteURL = feed.siteURL ?? parsed.siteURL
                library.feeds[index] = feed
                newArticles += add(parsed.items, of: feedID, to: &library, now: now, isFirstDownload: isFirstDownload)
            }
        }
        return newArticles
    }

    private static func add(
        _ items: [ParsedItem], of feedID: Feed.ID, to library: inout Library, now: Date, isFirstDownload: Bool
    ) -> [Article.ID] {
        let known = Set(library.articles.values.lazy.filter { $0.feedID == feedID }.map(\.key))
        let oldest = now.addingTimeInterval(-firstDownloadMaxAge)
        var added: [Article.ID] = []
        for item in items where !known.contains(item.key) {
            let key = Tombstone.Key(feedID: feedID, key: item.key)
            if library.tombstones[key] != nil {
                library.tombstones[key]?.lastSeen = now
                continue
            }
            if isFirstDownload, let published = item.published, published < oldest {
                library.tombstones[key] = Tombstone(feedID: feedID, key: item.key, lastSeen: now)
                continue
            }
            let article = Article(
                feedID: feedID, key: item.key, title: item.title, link: item.link, published: item.published,
                author: item.author, text: item.text, language: item.language, firstSeen: now)
            library.articles[article.id] = article
            added.append(article.id)
        }
        return added
    }
}
