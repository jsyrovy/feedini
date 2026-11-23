import Foundation

/// Downloads and parses all feeds off the main actor; merging the results is up to the caller (`FeedMerge`).
struct RefreshCoordinator: Sendable {
    var fetcher = FeedFetcher()

    @concurrent
    func refresh(_ feeds: [Feed]) async -> [Feed.ID: FeedRefresh] {
        let requests = feeds.map {
            FetchRequest(feedID: $0.id, url: $0.url, etag: $0.etag, lastModified: $0.lastModified)
        }
        let urls = Dictionary(uniqueKeysWithValues: feeds.map { ($0.id, $0.url) })
        let outcomes = await fetcher.fetchAll(requests)
        var refreshes: [Feed.ID: FeedRefresh] = [:]
        for (id, outcome) in outcomes {
            refreshes[id] = Self.refresh(from: outcome, url: urls[id])
        }
        let failed = refreshes.values.filter { if case .failed = $0 { true } else { false } }.count
        Log.refresh.info("Refreshed \(feeds.count) feeds, \(failed) failed")
        return refreshes
    }

    static func refresh(from outcome: FetchOutcome, url: URL?) -> FeedRefresh {
        switch outcome {
        case .notModified:
            return .notModified
        case .failed(let error):
            Log.feeds.error("\(url?.absoluteString ?? "?", privacy: .public): \(error.message, privacy: .public)")
            return .failed(error.message)
        case .fetched(let fetched):
            do {
                let parsed = try FeedParser.parse(fetched.data, baseURL: url)
                return .updated(parsed, etag: fetched.etag, lastModified: fetched.lastModified)
            } catch {
                Log.feeds.error("\(url?.absoluteString ?? "?", privacy: .public): \(error.message, privacy: .public)")
                return .failed(error.message)
            }
        }
    }
}

extension FeedParserError {
    var message: String {
        switch self {
        case .notAFeed: "This isn't an RSS or Atom feed."
        case .invalid(let detail): "The feed couldn't be read: \(detail)"
        }
    }
}
