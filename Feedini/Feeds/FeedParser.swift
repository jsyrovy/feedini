import Foundation

/// A feed as parsed, before it is merged into the library.
struct ParsedFeed: Sendable, Equatable {
    var title: String?
    var siteURL: URL?
    /// The raw language tag (`cs`, `en-US`, …).
    var language: String?
    /// In feed order, without duplicates.
    var items: [ParsedItem]
}

struct ParsedItem: Sendable, Equatable {
    /// The guid / Atom id, else the link, else the title.
    var key: String
    var title: String
    var link: URL?
    var published: Date?
    var author: String?
    /// Plain text: the full content when the feed has it, else the description / summary.
    var text: String
}

enum FeedParserError: Error, Equatable, Sendable {
    /// The document isn't RSS or Atom (typically a web page).
    case notAFeed
    /// The XML is broken and not a single article could be read.
    case invalid(String)
}

/// Parses RSS 0.9x / 1.0 / 2.0 and Atom with `XMLParser`.
///
/// The text of an item is converted to plain text (`HTMLText`) and cut to `maxTextLength`. Feeds that aren't
/// well-formed XML because of HTML entities (`&nbsp;`) or a bare `&` are repaired and parsed again.
enum FeedParser {
    static let maxTextLength = 10_000

    /// `baseURL` (the feed URL) resolves relative links.
    static func parse(_ data: Data, baseURL: URL? = nil) throws(FeedParserError) -> ParsedFeed {
        let first = parseOnce(data, baseURL: baseURL)
        if case .success(let feed) = first {
            return feed
        }
        let repaired = repairXML(data)
        if repaired != data, case .success(let feed) = parseOnce(repaired, baseURL: baseURL) {
            return feed
        }
        return try first.get()
    }

    private static func parseOnce(_ data: Data, baseURL: URL?) -> Result<ParsedFeed, FeedParserError> {
        let delegate = Delegate(baseURL: baseURL)
        let parser = XMLParser(data: data)
        parser.shouldProcessNamespaces = true
        parser.shouldResolveExternalEntities = false
        parser.delegate = delegate
        let succeeded = parser.parse()
        guard delegate.kind != nil else {
            if delegate.sawRoot || succeeded {
                return .failure(.notAFeed)
            }
            return .failure(.invalid(parser.parserError?.localizedDescription ?? "Unknown XML error"))
        }
        // A feed broken in the middle still gives the articles read up to there.
        guard succeeded || !delegate.items.isEmpty else {
            return .failure(.invalid(parser.parserError?.localizedDescription ?? "Unknown XML error"))
        }
        return .success(delegate.feed)
    }

    /// Makes common breakage well-formed: whitespace before the XML declaration, HTML named entities (replaced by
    /// character references) and bare ampersands (escaped). Works on bytes, so any ASCII-compatible encoding stays
    /// intact.
    static func repairXML(_ data: Data) -> Data {
        let bytes = Array(data.drop { $0 == 0x20 || $0 == 0x09 || $0 == 0x0A || $0 == 0x0D })
        let ampersand = UInt8(ascii: "&")
        let semicolon = UInt8(ascii: ";")
        let predefined: Set<String> = ["amp", "lt", "gt", "quot", "apos"]
        var output = [UInt8]()
        output.reserveCapacity(bytes.count)
        var index = 0
        while index < bytes.count {
            let byte = bytes[index]
            guard byte == ampersand else {
                output.append(byte)
                index += 1
                continue
            }
            var end = index + 1
            while end < bytes.count, end - index <= HTMLText.maxEntityLength,
                bytes[end] == UInt8(ascii: "#") || isASCIIAlphanumeric(bytes[end])
            {
                end += 1
            }
            let name = String(decoding: bytes[(index + 1)..<end], as: UTF8.self)
            if end < bytes.count, bytes[end] == semicolon, !name.isEmpty {
                if predefined.contains(name) || name.hasPrefix("#") {
                    output.append(contentsOf: bytes[index...end])
                } else if let scalar = HTMLText.namedEntities[name] {
                    output.append(contentsOf: Array("&#\(scalar);".utf8))
                } else {
                    output.append(contentsOf: Array("&amp;".utf8))
                    output.append(contentsOf: bytes[(index + 1)...end])
                }
                index = end + 1
            } else {
                output.append(contentsOf: Array("&amp;".utf8))
                index += 1
            }
        }
        return Data(output)
    }

    private static func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
        (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
    }

    // MARK: Dates

    /// RFC 822 dates of RSS, with the variations seen in the wild (no weekday, no seconds, zone names).
    static func rfc822Date(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in rfc822Formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return iso8601Date(trimmed)
    }

    // Formatters are expensive to create; they are thread-safe.
    private static let rfc822Formatters = [
        "EEE, dd MMM yyyy HH:mm:ss zzz", "EEE, dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm zzz",
        "EEE, dd MMM yyyy HH:mm Z", "dd MMM yyyy HH:mm:ss zzz", "dd MMM yyyy HH:mm:ss Z", "EEE, dd MMM yyyy HH:mm:ss",
    ].map { format in
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "UTC")
        formatter.dateFormat = format
        return formatter
    }

    /// ISO 8601 dates of Atom and Dublin Core, with or without fractional seconds, or just a day.
    static func iso8601Date(_ string: String) -> Date? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        for formatter in iso8601Formatters {
            if let date = formatter.date(from: trimmed) {
                return date
            }
        }
        return nil
    }

    nonisolated(unsafe) private static let iso8601Formatters = [
        [.withInternetDateTime], [.withInternetDateTime, .withFractionalSeconds], [.withFullDate],
    ].map { (options: ISO8601DateFormatter.Options) in
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = options
        return formatter
    }
}

// MARK: - XMLParser delegate

private enum Namespace {
    static let atom = "http://www.w3.org/2005/Atom"
    static let rss1 = "http://purl.org/rss/1.0/"
    static let rdf = "http://www.w3.org/1999/02/22-rdf-syntax-ns#"
    static let content = "http://purl.org/rss/1.0/modules/content/"
    static let dublinCore = "http://purl.org/dc/elements/1.1/"
}

private final class Delegate: NSObject, XMLParserDelegate {
    enum Kind {
        case rss, atom
    }

    private struct Element {
        var namespace: String
        var name: String
        var attributes: [String: String]
    }

    private struct ItemFields {
        var id: String?
        var title: String?
        var link: String?
        var published: Date?
        var updated: Date?
        var author: String?
        var summary: String?
        var content: String?
    }

    let baseURL: URL?
    private(set) var kind: Kind?
    private(set) var sawRoot = false
    private(set) var items: [ParsedItem] = []
    private var title: String?
    private var siteLink: String?
    private var language: String?
    private var keys = Set<String>()

    private var stack: [Element] = []
    private var text = ""
    private var item: ItemFields?
    /// Depth of the Atom `content` / `summary` element with `type="xhtml"` being collected as markup.
    private var xhtmlDepth: Int?

    init(baseURL: URL?) {
        self.baseURL = baseURL
    }

    var feed: ParsedFeed {
        ParsedFeed(
            title: title.map(HTMLText.plainText).flatMap { $0.isEmpty ? nil : $0 },
            siteURL: siteLink.flatMap(resolve), language: language, items: items)
    }

    func parser(
        _ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?,
        attributes: [String: String] = [:]
    ) {
        let namespace = namespaceURI ?? ""
        if stack.isEmpty {
            sawRoot = true
            switch (namespace, name) {
            case ("", "rss"), (Namespace.rdf, "RDF"): kind = .rss
            case (Namespace.atom, "feed"):
                kind = .atom
                language = attributes["xml:lang"] ?? attributes["lang"]
            default: parser.abortParsing()
            }
        }
        if let depth = xhtmlDepth, stack.count >= depth {
            text += "<\(name)>"
        } else {
            text = ""
        }
        stack.append(Element(namespace: namespace, name: name, attributes: attributes))

        switch (kind, namespace, name) {
        case (.rss, "", "item"), (.rss, Namespace.rss1, "item"), (.atom, Namespace.atom, "entry"):
            item = ItemFields()
        case (.atom, Namespace.atom, "content"), (.atom, Namespace.atom, "summary"):
            if attributes["type"] == "xhtml" {
                xhtmlDepth = stack.count
            }
        case (.atom, Namespace.atom, "link"):
            atomLink(attributes)
        default:
            break
        }
    }

    func parser(_ parser: XMLParser, foundCharacters string: String) {
        text += string
    }

    func parser(_ parser: XMLParser, foundCDATA block: Data) {
        text += String(decoding: block, as: UTF8.self)
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let element = stack.popLast() else { return }
        if let depth = xhtmlDepth {
            if stack.count >= depth {
                text += "</\(name)>"
                return
            }
            xhtmlDepth = nil
        }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parent = stack.last.map { ($0.namespace, $0.name) }
        switch kind {
        case .rss: endRSS(element, value: value, parent: parent)
        case .atom: endAtom(element, value: value, parent: parent)
        case nil: break
        }
        text = ""
    }

    // MARK: RSS

    private func endRSS(_ element: Element, value: String, parent: (String, String)?) {
        let isItem = item != nil
        switch (element.namespace, element.name, isItem) {
        case ("", "item", true), (Namespace.rss1, "item", true):
            finishItem()
        case ("", "title", true), (Namespace.rss1, "title", true):
            item?.title = value
        case ("", "link", true), (Namespace.rss1, "link", true):
            item?.link = value
        case ("", "guid", true):
            item?.id = value
        case ("", "pubDate", true):
            item?.published = FeedParser.rfc822Date(value)
        case (Namespace.dublinCore, "date", true):
            item?.updated = FeedParser.iso8601Date(value)
        case ("", "description", true), (Namespace.rss1, "description", true):
            item?.summary = value
        case (Namespace.content, "encoded", true):
            item?.content = value
        case (Namespace.dublinCore, "creator", true):
            item?.author = value
        case ("", "author", true):
            if item?.author == nil {
                item?.author = Self.rssAuthor(value)
            }
        case ("", "title", false), (Namespace.rss1, "title", false):
            if isChannel(parent) {
                title = value
            }
        case ("", "link", false), (Namespace.rss1, "link", false):
            if isChannel(parent) {
                siteLink = value
            }
        case ("", "language", false), (Namespace.dublinCore, "language", false):
            if isChannel(parent) {
                language = value
            }
        default:
            break
        }
    }

    private func isChannel(_ parent: (String, String)?) -> Bool {
        guard let parent else { return false }
        return parent == ("", "channel") || parent == (Namespace.rss1, "channel")
    }

    /// RSS `<author>` is an e-mail address, usually followed by the name in parentheses.
    static func rssAuthor(_ value: String) -> String? {
        if let open = value.firstIndex(of: "("), let close = value.lastIndex(of: ")"), open < close {
            let name = value[value.index(after: open)..<close].trimmingCharacters(in: .whitespaces)
            if !name.isEmpty {
                return name
            }
        }
        return value.isEmpty ? nil : value
    }

    // MARK: Atom

    private func endAtom(_ element: Element, value: String, parent: (String, String)?) {
        guard element.namespace == Namespace.atom else { return }
        let inEntry = item != nil
        let parentName = parent.flatMap { $0.0 == Namespace.atom ? $0.1 : nil }
        switch (element.name, inEntry) {
        case ("entry", true):
            finishItem()
        case ("title", true) where parentName == "entry":
            item?.title = atomText(value, type: element.attributes["type"])
        case ("id", true) where parentName == "entry":
            item?.id = value
        case ("published", true):
            item?.published = FeedParser.iso8601Date(value)
        case ("updated", true) where parentName == "entry":
            item?.updated = FeedParser.iso8601Date(value)
        case ("summary", true):
            item?.summary = atomText(value, type: element.attributes["type"])
        case ("content", true):
            item?.content = atomText(value, type: element.attributes["type"])
        case ("name", true) where parentName == "author":
            if item?.author == nil {
                item?.author = value
            }
        case ("title", false) where parentName == "feed":
            title = atomText(value, type: element.attributes["type"])
        default:
            break
        }
    }

    /// Atom text constructs: plain `text` is escaped for the HTML conversion that follows.
    private func atomText(_ value: String, type: String?) -> String {
        guard type == nil || type == "text" else { return value }
        return value.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
    }

    private func atomLink(_ attributes: [String: String]) {
        guard let href = attributes["href"] else { return }
        let rel = attributes["rel"] ?? "alternate"
        guard rel == "alternate" else { return }
        let parentName = stack.dropLast().last.map(\.name)
        if item != nil, parentName == "entry" {
            if item?.link == nil {
                item?.link = href
            }
        } else if item == nil, parentName == "feed" {
            siteLink = siteLink ?? href
        }
    }

    // MARK: Items

    private func finishItem() {
        guard let fields = item else { return }
        item = nil
        let link = fields.link.flatMap(resolve)
        let html = [fields.content, fields.summary].compactMap { $0 }.first { !$0.isEmpty } ?? ""
        var text = HTMLText.plainText(html)
        if text.count > FeedParser.maxTextLength {
            text = text.prefix(FeedParser.maxTextLength - 1) + "…"
        }
        let title = HTMLText.plainText(fields.title ?? "")
        let key = [fields.id, link?.absoluteString, title].compactMap { $0 }.first { !$0.isEmpty }
        guard let key, keys.insert(key).inserted else { return }
        items.append(
            ParsedItem(
                key: key, title: title.isEmpty ? HTMLText.excerpt(text, limit: 80) : title, link: link,
                published: fields.published ?? fields.updated,
                author: fields.author.map(HTMLText.plainText).flatMap { $0.isEmpty ? nil : $0 }, text: text))
    }

    /// An absolute web URL; relative links are resolved against the feed URL.
    private func resolve(_ string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        let url =
            URL(string: trimmed, relativeTo: baseURL)
            ?? trimmed.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed).flatMap {
                URL(string: $0, relativeTo: baseURL)
            }
        guard let absolute = url?.absoluteURL, ["http", "https"].contains(absolute.scheme?.lowercased()) else {
            return nil
        }
        return absolute
    }
}
