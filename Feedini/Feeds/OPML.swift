import Foundation

/// Reads and writes OPML subscription lists.
enum OPML {
    /// A feed listed in an OPML file. The URL is kept as written; checking it (HTTPS, a real feed) is up to the
    /// caller.
    struct Entry: Sendable, Equatable {
        var title: String
        var feedURL: String
        var siteURL: String?
    }

    enum ParseError: Error, Equatable, Sendable {
        case notOPML
        case invalid(String)
    }

    /// The feeds of all outlines with an `xmlUrl`, nested ones (categories) included, in document order and without
    /// duplicate URLs.
    static func parse(_ data: Data) throws(ParseError) -> [Entry] {
        let delegate = Delegate()
        let parser = XMLParser(data: data)
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let succeeded = parser.parse()
        guard delegate.isOPML else {
            if succeeded || delegate.sawRoot {
                throw .notOPML
            }
            throw .invalid(parser.parserError?.localizedDescription ?? "Unknown XML error")
        }
        guard succeeded else {
            throw .invalid(parser.parserError?.localizedDescription ?? "Unknown XML error")
        }
        return delegate.entries
    }

    /// An OPML 2.0 document listing the feeds.
    static func export(_ feeds: [Feed], title: String = "Feedini subscriptions") -> Data {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>\(escape(title))</title>",
            "  </head>",
            "  <body>",
        ]
        for feed in feeds {
            var attributes = [
                "type=\"rss\"", "text=\"\(escape(feed.title))\"", "title=\"\(escape(feed.title))\"",
                "xmlUrl=\"\(escape(feed.url.absoluteString))\"",
            ]
            if let site = feed.siteURL {
                attributes.append("htmlUrl=\"\(escape(site.absoluteString))\"")
            }
            lines.append("    <outline \(attributes.joined(separator: " "))/>")
        }
        lines += ["  </body>", "</opml>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
            .replacingOccurrences(of: "\n", with: "&#10;")
    }

    private final class Delegate: NSObject, XMLParserDelegate {
        private(set) var sawRoot = false
        private(set) var isOPML = false
        private(set) var entries: [Entry] = []
        private var seen = Set<String>()

        func parser(
            _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
            attributes: [String: String] = [:]
        ) {
            if !sawRoot {
                sawRoot = true
                isOPML = name.lowercased() == "opml"
                if !isOPML {
                    parser.abortParsing()
                }
                return
            }
            guard name == "outline" else { return }
            // Attribute names vary in case between exporters (`xmlUrl`, `xmlURL`, `xmlurl`).
            let lowercased = Dictionary(
                attributes.map { ($0.key.lowercased(), $0.value) }, uniquingKeysWith: { first, _ in first })
            guard let url = lowercased["xmlurl"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty,
                seen.insert(url).inserted
            else { return }
            let title = [lowercased["title"], lowercased["text"]].compactMap { $0 }.first { !$0.isEmpty } ?? url
            entries.append(Entry(title: title, feedURL: url, siteURL: lowercased["htmlurl"]))
        }
    }
}
