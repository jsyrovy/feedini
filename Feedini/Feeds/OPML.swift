import Foundation

/// Reads and writes OPML subscription lists.
enum OPML {
    /// A feed listed in an OPML file. The URL is kept as written; checking it (HTTPS, a real feed) is up to the
    /// caller.
    struct Entry: Sendable, Equatable {
        var title: String
        var feedURL: String
        var siteURL: String?
        /// The name of the nearest category (an outline without `xmlUrl`) the feed is nested in.
        var folder: String?
    }

    enum ParseError: Error, Equatable, Sendable {
        case notOPML
        case invalid(String)
    }

    /// The feeds of all outlines with an `xmlUrl`, nested ones (categories) included, in document order and without
    /// duplicate URLs (the first one wins). A feed nested in categories gets the name of the nearest one as its folder;
    /// deeper levels aren't kept.
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

    /// An OPML 2.0 document listing the feeds: those in a folder in a category outline (folders in their order, empty
    /// ones left out), then the others.
    static func export(_ feeds: [Feed], folders: [Folder] = [], title: String = "Feedini subscriptions") -> Data {
        var lines = [
            #"<?xml version="1.0" encoding="UTF-8"?>"#,
            #"<opml version="2.0">"#,
            "  <head>",
            "    <title>\(escape(title))</title>",
            "  </head>",
            "  <body>",
        ]
        let known = Set(folders.map(\.id))
        for folder in folders {
            let inFolder = feeds.filter { $0.folderID == folder.id }
            guard !inFolder.isEmpty else { continue }
            lines.append("    <outline text=\"\(escape(folder.name))\" title=\"\(escape(folder.name))\">")
            lines += inFolder.map { outline($0, indent: "      ") }
            lines.append("    </outline>")
        }
        lines += feeds.filter { $0.folderID.map { !known.contains($0) } ?? true }.map { outline($0, indent: "    ") }
        lines += ["  </body>", "</opml>", ""]
        return Data(lines.joined(separator: "\n").utf8)
    }

    private static func outline(_ feed: Feed, indent: String) -> String {
        var attributes = [
            "type=\"rss\"", "text=\"\(escape(feed.title))\"", "title=\"\(escape(feed.title))\"",
            "xmlUrl=\"\(escape(feed.url.absoluteString))\"",
        ]
        if let site = feed.siteURL {
            attributes.append("htmlUrl=\"\(escape(site.absoluteString))\"")
        }
        return "\(indent)<outline \(attributes.joined(separator: " "))/>"
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
        /// The open outlines: the name of a category, `nil` for a feed (or a category without a name).
        private var outlines: [String?] = []

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
            let title = [lowercased["title"], lowercased["text"]].compactMap {
                $0?.trimmingCharacters(in: .whitespacesAndNewlines)
            }.first { !$0.isEmpty }
            guard let url = lowercased["xmlurl"]?.trimmingCharacters(in: .whitespacesAndNewlines), !url.isEmpty else {
                outlines.append(title)
                return
            }
            let folder = outlines.last { $0 != nil } ?? nil
            outlines.append(nil)
            guard seen.insert(url).inserted else { return }
            entries.append(Entry(title: title ?? url, feedURL: url, siteURL: lowercased["htmlurl"], folder: folder))
        }

        func parser(
            _ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?
        ) {
            if name == "outline" {
                _ = outlines.popLast()
            }
        }
    }
}
