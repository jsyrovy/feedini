import Foundation

/// Checks a feed address the user typed (or an OPML entry) before it is added: only HTTPS, a real RSS / Atom feed,
/// not subscribed yet.
struct FeedSubscriber: Sendable {
    /// A checked feed, with what its first download gave, so its articles can be added right away.
    struct Subscription: Sendable, Equatable {
        var url: URL
        var parsed: ParsedFeed
        var etag: String?
        var lastModified: String?

        /// The feed's title, or its host when it has none.
        var title: String {
            parsed.title ?? url.host() ?? url.absoluteString
        }
    }

    enum Failure: Error, Sendable, Equatable {
        case invalidAddress
        /// An `http://` address whose HTTPS variant doesn't work.
        case notHTTPS(String)
        case alreadySubscribed
        case unreachable(String)
        case notAFeed(String)

        var message: String {
            switch self {
            case .invalidAddress: "This isn't a web address."
            case .notHTTPS(let reason):
                "Only HTTPS feeds are supported, and this feed doesn't work over HTTPS (\(reason.trimmingSuffix("."))."
            case .alreadySubscribed: "You already follow this feed."
            case .unreachable(let reason), .notAFeed(let reason): reason
            }
        }
    }

    var fetcher = FeedFetcher()

    /// The HTTPS address to try for what the user typed: a missing scheme and `http://` / `feed://` become
    /// `https://`. Returns whether the user asked for plain HTTP, which changes the error message.
    static func httpsURL(for input: String) -> (url: URL, wasHTTP: Bool)? {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !text.contains(where: \.isWhitespace) else { return nil }
        var wasHTTP = false
        let lowercased = text.lowercased()
        if lowercased.hasPrefix("http://") {
            text = "https://" + text.dropFirst("http://".count)
            wasHTTP = true
        } else if lowercased.hasPrefix("feed://") {
            text = "https://" + text.dropFirst("feed://".count)
        } else if !lowercased.hasPrefix("https://") {
            guard !text.contains("://") else { return nil }
            text = "https://" + text
        }
        guard let url = URL(string: text), let host = url.host(), host.contains(".") || host == "localhost" else {
            return nil
        }
        return (url, wasHTTP)
    }

    /// Whether two feed URLs are the same feed (scheme and host case, a trailing slash don't matter).
    static func isSame(_ lhs: URL, _ rhs: URL) -> Bool {
        normalized(lhs) == normalized(rhs)
    }

    private static func normalized(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url.absoluteString
        }
        components.scheme = components.scheme?.lowercased()
        components.host = components.host?.lowercased()
        var text = components.string ?? url.absoluteString
        if text.hasSuffix("/") {
            text.removeLast()
        }
        return text
    }

    func subscribe(_ input: String, existing: [URL]) async -> Result<Subscription, Failure> {
        guard let (url, wasHTTP) = Self.httpsURL(for: input) else { return .failure(.invalidAddress) }
        guard !existing.contains(where: { Self.isSame($0, url) }) else { return .failure(.alreadySubscribed) }
        let outcome = await fetcher.fetch(FetchRequest(feedID: UUID(), url: url))
        switch outcome {
        case .fetched(let fetched):
            do {
                let parsed = try FeedParser.parse(fetched.data, baseURL: url)
                return .success(
                    Subscription(url: url, parsed: parsed, etag: fetched.etag, lastModified: fetched.lastModified))
            } catch {
                return .failure(wasHTTP ? .notHTTPS(error.message) : .notAFeed(error.message))
            }
        case .notModified:
            return .failure(.unreachable("The server answered “not modified” to a first download."))
        case .failed(let error):
            return .failure(wasHTTP ? .notHTTPS(error.message) : .unreachable(error.message))
        }
    }

    struct ImportResult: Sendable, Equatable {
        var added: [Subscription] = []
        /// Entries not added, with the reason.
        var skipped: [(entry: OPML.Entry, reason: String)] = []

        static func == (lhs: ImportResult, rhs: ImportResult) -> Bool {
            lhs.added == rhs.added && lhs.skipped.map(\.entry) == rhs.skipped.map(\.entry)
                && lhs.skipped.map(\.reason) == rhs.skipped.map(\.reason)
        }
    }

    /// Checks OPML entries `FeedFetcher.maxConcurrentDownloads` at a time; the result keeps the OPML order.
    func subscribe(_ entries: [OPML.Entry], existing: [URL]) async -> ImportResult {
        let results = await withTaskGroup(of: (Int, Result<Subscription, Failure>).self) { group in
            var pending = Array(entries.enumerated())[...]
            var results: [Int: Result<Subscription, Failure>] = [:]
            for _ in 0..<FeedFetcher.maxConcurrentDownloads {
                guard let (index, entry) = pending.popFirst() else { break }
                group.addTask { (index, await subscribe(entry.feedURL, existing: existing)) }
            }
            while let (index, result) = await group.next() {
                results[index] = result
                if let (index, entry) = pending.popFirst() {
                    group.addTask { (index, await subscribe(entry.feedURL, existing: existing)) }
                }
            }
            return results
        }
        var result = ImportResult()
        for (index, entry) in entries.enumerated() {
            switch results[index] {
            case .success(let subscription):
                // The same feed under two addresses (http and https) is added once.
                if result.added.contains(where: { Self.isSame($0.url, subscription.url) }) {
                    result.skipped.append((entry, Failure.alreadySubscribed.message))
                } else {
                    result.added.append(subscription)
                }
            case .failure(let failure):
                result.skipped.append((entry, failure.message))
            case nil:
                break
            }
        }
        return result
    }
}

extension String {
    fileprivate func trimmingSuffix(_ suffix: String) -> String {
        hasSuffix(suffix) ? String(dropLast(suffix.count)) : self
    }
}
