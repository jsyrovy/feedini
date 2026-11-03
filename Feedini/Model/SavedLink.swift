import Foundation

/// A web page saved by its address (Save Link…): an article of no feed, in Saved only. Its text is the page's text
/// (`Library.pageTextIDs`); its title and source come from the page. It is kept only while it is saved – removed from
/// Saved, it goes at the next prune like the saved articles of a removed feed.
enum SavedLink {
    /// The feed ID of saved links. No feed has it.
    static let feedID = UUID(uuidString: "FEED0000-5A7E-411C-8000-000000000001")!

    enum Failure: Error, Sendable, Equatable {
        case invalidAddress

        var message: String { "This isn't a web address." }
    }

    enum Outcome: Equatable, Sendable {
        /// A new saved link.
        case added(Article.ID)
        /// An article that was there already – of a feed, or a link removed from Saved – is saved.
        case saved(Article.ID)
        /// The article is saved already; nothing changed.
        case alreadySaved(Article.ID)
    }

    /// The HTTPS address for what the user typed: a missing scheme and `http://` become `https://`, as for feeds.
    static func url(from address: String) throws(Failure) -> URL {
        guard let url = FeedSubscriber.httpsURL(for: address)?.url else { throw .invalidAddress }
        return url
    }

    /// Text from the clipboard to offer as the address: only an `http(s)://` address – other text wasn't copied as one.
    static func offeredAddress(_ text: String?) -> String? {
        guard let text = text?.trimmingCharacters(in: .whitespacesAndNewlines),
            ["http://", "https://"].contains(where: text.lowercased().hasPrefix), (try? url(from: text)) != nil
        else { return nil }
        return text
    }

    /// Query parameters that only track where a link was shared, besides `utm_…`.
    private static let trackingParameters: Set<String> = [
        "fbclid", "gclid", "dclid", "msclkid", "yclid", "igshid", "mc_cid", "mc_eid", "_ga",
    ]

    /// The address as links are compared: without the scheme, the fragment, tracking parameters and a trailing slash,
    /// the host in lowercase (`example.com/news/a?id=1`).
    static func key(of url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false), let host = components.host
        else { return url.absoluteString }
        components.scheme = nil
        components.fragment = nil
        components.host = host.lowercased()
        if components.port == 80 || components.port == 443 {
            components.port = nil
        }
        if components.percentEncodedPath.hasSuffix("/") {
            components.percentEncodedPath.removeLast()
        }
        let query = components.percentEncodedQueryItems?.filter { item in
            let name = item.name.lowercased()
            return !name.hasPrefix("utm_") && !trackingParameters.contains(name)
        }
        components.percentEncodedQueryItems = query?.isEmpty == false ? query : nil
        let text = components.string ?? url.absoluteString
        return text.hasPrefix("//") ? String(text.dropFirst(2)) : text
    }

    /// The source shown until the page says its name: the host without `www.`.
    static func site(of url: URL) -> String? {
        guard let host = url.host()?.lowercased() else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }

    /// The title shown until the page is loaded: the address without the scheme.
    static func placeholderTitle(of url: URL) -> String {
        let text = url.absoluteString
        guard let range = text.range(of: "://") else { return text }
        return String(text[range.upperBound...])
    }
}

extension Article {
    /// Saved by its address, not from a feed (`SavedLink`).
    var isSavedLink: Bool { feedID == SavedLink.feedID }
}

extension Library {
    /// The article at the address (`SavedLink.key`): a saved link before an article of a feed, a saved article before
    /// one that isn't.
    func article(at url: URL) -> Article? {
        let key = SavedLink.key(of: url)
        let matching = articles.values.filter { article in
            (article.isSavedLink && article.key == key) || article.link.map(SavedLink.key) == key
        }
        return matching.min { lhs, rhs in
            let left = (lhs.isSavedLink ? 0 : 1, lhs.isSaved ? 0 : 1, lhs.firstSeen, lhs.id.uuidString)
            let right = (rhs.isSavedLink ? 0 : 1, rhs.isSaved ? 0 : 1, rhs.firstSeen, rhs.id.uuidString)
            return left < right
        }
    }

    /// Saves the page at the address: the article that is there already, or a new saved link (unread, its title and
    /// source from the address until the page is loaded).
    mutating func saveLink(_ url: URL, at date: Date) -> SavedLink.Outcome {
        if let article = article(at: url) {
            guard !article.isSaved else { return .alreadySaved(article.id) }
            articles[article.id]?.savedAt = date
            return .saved(article.id)
        }
        let article = Article(
            feedID: SavedLink.feedID, key: SavedLink.key(of: url), title: SavedLink.placeholderTitle(of: url),
            link: url, firstSeen: date, savedAt: date, site: SavedLink.site(of: url))
        articles[article.id] = article
        return .added(article.id)
    }

    /// Fills in what the page says about a saved link: its title, site, author and date. The address stays as the
    /// user gave it (a page may redirect to its cookie consent). Articles of feeds keep what their feed says.
    mutating func applyPageMetadata(_ metadata: PageMetadata, to id: Article.ID) {
        guard var article = articles[id], article.isSavedLink else { return }
        article.title = metadata.title ?? article.title
        article.site = metadata.site ?? article.site
        article.author = metadata.author ?? article.author
        article.published = metadata.published ?? article.published
        articles[id] = article
    }
}
