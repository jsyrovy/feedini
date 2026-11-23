import Foundation

/// What a loaded page gives: its text, and what it says about itself.
struct PageContent: Sendable, Equatable {
    var text: String
    var metadata: PageMetadata
}

/// What a page says about itself (`PageScript.metadata`: Open Graph and other meta tags, JSON-LD, `<title>`); saved
/// links take their title, source and date from it.
struct PageMetadata: Sendable, Equatable {
    var title: String?
    /// The name of the web site.
    var site: String?
    var author: String?
    var published: Date?
}

extension PageMetadata {
    /// The values as the script returns them.
    private struct Raw: Decodable {
        var title: String?
        var site: String?
        var author: String?
        var published: String?
    }

    /// From the script's JSON, cleaned: whitespace collapsed, empty values and authors that are addresses (profile
    /// links) left out, the site's name cut from the end of the title.
    init(json: String) {
        let raw = (try? JSONDecoder().decode(Raw.self, from: Data(json.utf8))) ?? Raw()
        site = Self.cleaned(raw.site)
        title = Self.cleaned(raw.title).map { Self.title($0, withoutSite: site) }
        author = Self.cleaned(raw.author).flatMap { $0.contains("://") ? nil : $0 }
        published = raw.published.flatMap(FeedParser.iso8601Date)
    }

    private static func cleaned(_ text: String?) -> String? {
        guard let text else { return nil }
        let cleaned = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return cleaned.isEmpty ? nil : cleaned
    }

    /// "Title | Site", "Title - Site" and the like without the site.
    private static func title(_ title: String, withoutSite site: String?) -> String {
        guard let site else { return title }
        for separator in [" | ", " - ", " – ", " — ", " · "] {
            let suffix = separator + site
            if title.count > suffix.count, title.lowercased().hasSuffix(suffix.lowercased()) {
                return String(title.dropLast(suffix.count))
            }
        }
        return title
    }
}
