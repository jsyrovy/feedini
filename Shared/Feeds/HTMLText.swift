import Foundation

/// Turns the HTML found in feeds into plain text. A small scanner, not a browser: it only needs to keep the words,
/// paragraphs and list items, and never loads anything.
enum HTMLText {
    /// Plain text of an HTML fragment: paragraphs separated by a blank line, line breaks kept, list items with a
    /// bullet, whitespace collapsed, entities decoded, scripts, styles and comments dropped.
    static func plainText(_ html: String) -> String {
        var builder = TextBuilder()
        var skipping: String?
        var index = html.startIndex
        while index < html.endIndex {
            guard html[index] == "<", let tag = Tag(in: html, at: index) else {
                let next = html[index...].dropFirst().firstIndex(of: "<") ?? html.endIndex
                if skipping == nil {
                    builder.append(decodeEntities(String(html[index..<next])))
                }
                index = next
                continue
            }
            index = tag.end
            if let skipped = skipping {
                if tag.isClosing && tag.name == skipped {
                    skipping = nil
                }
                continue
            }
            if !tag.isClosing && !tag.isSelfClosing && skippedElements.contains(tag.name) {
                skipping = tag.name
            } else if tag.name == "br" {
                builder.breakLine()
            } else if tag.name == "li" && !tag.isClosing {
                builder.breakLine()
                builder.append("• ")
            } else if blockElements.contains(tag.name) {
                builder.breakParagraph()
            }
        }
        return builder.text
    }

    /// The text on one line, cut at a word boundary to at most `limit` characters (plus "…").
    static func excerpt(_ text: String, limit: Int) -> String {
        let line = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        guard line.count > limit else { return line }
        let cut = line.prefix(limit)
        let endsAtWord = line[cut.endIndex].isWhitespace
        let words = endsAtWord ? cut : cut.lastIndex(of: " ").map { cut[..<$0] } ?? cut
        return words.trimmingCharacters(in: CharacterSet(charactersIn: " ,.;:–-")) + "…"
    }

    /// Decodes character references (`&amp;`, `&#8211;`, `&#x2019;`) and the common named HTML entities. Unknown
    /// ones are left as they are.
    static func decodeEntities(_ text: String) -> String {
        guard text.contains("&") else { return text }
        var result = ""
        var index = text.startIndex
        while let ampersand = text[index...].firstIndex(of: "&") {
            result += text[index..<ampersand]
            let rest = text[ampersand...].prefix(maxEntityLength)
            if let semicolon = rest.firstIndex(of: ";"),
                let scalar = scalar(forEntity: text[text.index(after: ampersand)..<semicolon])
            {
                result.unicodeScalars.append(scalar)
                index = text.index(after: semicolon)
            } else {
                result += "&"
                index = text.index(after: ampersand)
            }
        }
        result += text[index...]
        return result
    }

    /// The character an entity name (`amp`, `#8211`, `#x2019`) stands for.
    static func scalar(forEntity name: Substring) -> Unicode.Scalar? {
        if name.hasPrefix("#x") || name.hasPrefix("#X") {
            return UInt32(name.dropFirst(2), radix: 16).flatMap(Unicode.Scalar.init)
        }
        if name.hasPrefix("#") {
            return UInt32(name.dropFirst()).flatMap(Unicode.Scalar.init)
        }
        return namedEntities[String(name)].flatMap(Unicode.Scalar.init)
    }

    static let maxEntityLength = 12

    /// Elements whose content is not text.
    private static let skippedElements: Set<String> = [
        "script", "style", "noscript", "template", "svg", "head", "title", "iframe", "object",
    ]

    private static let blockElements: Set<String> = [
        "p", "div", "ul", "ol", "dl", "dt", "dd", "h1", "h2", "h3", "h4", "h5", "h6", "blockquote", "pre", "table",
        "tr", "section", "article", "header", "footer", "aside", "figure", "figcaption", "hr", "address", "details",
        "summary", "main", "nav",
    ]

    /// Named entities beyond the five of XML that feeds commonly use.
    static let namedEntities: [String: UInt32] = [
        "amp": 38, "lt": 60, "gt": 62, "quot": 34, "apos": 39, "nbsp": 160, "iexcl": 161, "cent": 162,
        "pound": 163, "curren": 164, "yen": 165, "brvbar": 166, "sect": 167, "uml": 168, "copy": 169, "ordf": 170,
        "laquo": 171, "not": 172, "shy": 173, "reg": 174, "macr": 175, "deg": 176, "plusmn": 177, "sup2": 178,
        "sup3": 179, "acute": 180, "micro": 181, "para": 182, "middot": 183, "cedil": 184, "sup1": 185, "ordm": 186,
        "raquo": 187, "frac14": 188, "frac12": 189, "frac34": 190, "iquest": 191, "Agrave": 192, "Aacute": 193,
        "Acirc": 194, "Atilde": 195, "Auml": 196, "Aring": 197, "AElig": 198, "Ccedil": 199, "Egrave": 200,
        "Eacute": 201, "Ecirc": 202, "Euml": 203, "Igrave": 204, "Iacute": 205, "Icirc": 206, "Iuml": 207,
        "ETH": 208, "Ntilde": 209, "Ograve": 210, "Oacute": 211, "Ocirc": 212, "Otilde": 213, "Ouml": 214,
        "times": 215, "Oslash": 216, "Ugrave": 217, "Uacute": 218, "Ucirc": 219, "Uuml": 220, "Yacute": 221,
        "THORN": 222, "szlig": 223, "agrave": 224, "aacute": 225, "acirc": 226, "atilde": 227, "auml": 228,
        "aring": 229, "aelig": 230, "ccedil": 231, "egrave": 232, "eacute": 233, "ecirc": 234, "euml": 235,
        "igrave": 236, "iacute": 237, "icirc": 238, "iuml": 239, "eth": 240, "ntilde": 241, "ograve": 242,
        "oacute": 243, "ocirc": 244, "otilde": 245, "ouml": 246, "divide": 247, "oslash": 248, "ugrave": 249,
        "uacute": 250, "ucirc": 251, "uuml": 252, "yacute": 253, "thorn": 254, "yuml": 255, "Ccaron": 268,
        "ccaron": 269, "Dcaron": 270, "dcaron": 271, "Ecaron": 282, "ecaron": 283, "Ncaron": 327, "ncaron": 328,
        "Rcaron": 344, "rcaron": 345, "Scaron": 352, "scaron": 353, "Tcaron": 356, "tcaron": 357, "Uring": 366,
        "uring": 367, "Zcaron": 381, "zcaron": 382, "OElig": 338, "oelig": 339, "fnof": 402, "circ": 710,
        "tilde": 732, "ensp": 8194, "emsp": 8195, "thinsp": 8201, "zwnj": 8204, "zwj": 8205, "lrm": 8206,
        "rlm": 8207, "ndash": 8211, "mdash": 8212, "lsquo": 8216, "rsquo": 8217, "sbquo": 8218, "ldquo": 8220,
        "rdquo": 8221, "bdquo": 8222, "dagger": 8224, "Dagger": 8225, "bull": 8226, "hellip": 8230,
        "permil": 8240, "prime": 8242, "Prime": 8243, "lsaquo": 8249, "rsaquo": 8250, "euro": 8364,
        "trade": 8482, "larr": 8592, "uarr": 8593, "rarr": 8594, "darr": 8595, "harr": 8596, "minus": 8722,
        "le": 8804, "ge": 8805, "ne": 8800, "asymp": 8776, "infin": 8734,
    ]

    /// A tag starting at `<`: `<p class="x">`, `</p>`, `<br/>`, `<!-- … -->`, `<!DOCTYPE …>`.
    private struct Tag {
        var name: String
        var isClosing: Bool
        var isSelfClosing: Bool
        /// Just after the tag.
        var end: String.Index

        init?(in html: String, at start: String.Index) {
            let afterBracket = html.index(after: start)
            guard afterBracket < html.endIndex else { return nil }
            let first = html[afterBracket]
            if html[afterBracket...].hasPrefix("!--") {
                let close = html[afterBracket...].range(of: "-->")
                self.init(name: "!--", isClosing: false, isSelfClosing: true, end: close?.upperBound ?? html.endIndex)
                return
            }
            guard first.isLetter || first == "/" || first == "!" || first == "?" else { return nil }
            guard let close = html[afterBracket...].firstIndex(of: ">") else { return nil }
            let inner = html[afterBracket..<close]
            let isClosing = inner.hasPrefix("/")
            let name = inner.drop { $0 == "/" }.prefix { $0.isLetter || $0.isNumber }.lowercased()
            self.init(
                name: name, isClosing: isClosing, isSelfClosing: inner.hasSuffix("/") || first == "!" || first == "?",
                end: html.index(after: close))
        }

        private init(name: String, isClosing: Bool, isSelfClosing: Bool, end: String.Index) {
            self.name = name
            self.isClosing = isClosing
            self.isSelfClosing = isSelfClosing
            self.end = end
        }
    }

    /// Collects text with collapsed whitespace and pending line / paragraph breaks, which are only written between
    /// two pieces of text (never at the start or the end).
    private struct TextBuilder {
        private enum Break: Int, Comparable {
            case none, space, line, paragraph

            static func < (lhs: Break, rhs: Break) -> Bool { lhs.rawValue < rhs.rawValue }
        }

        private(set) var text = ""
        private var pending = Break.none

        mutating func append(_ piece: String) {
            let startsWithSpace = piece.first?.isWhitespace ?? false
            let endsWithSpace = piece.last?.isWhitespace ?? false
            let words = piece.split(whereSeparator: \.isWhitespace)
            guard !words.isEmpty else {
                if !piece.isEmpty {
                    pending = max(pending, .space)
                }
                return
            }
            if startsWithSpace {
                pending = max(pending, .space)
            }
            if !text.isEmpty {
                switch pending {
                case .none: break
                case .space: text += " "
                case .line: text += "\n"
                case .paragraph: text += "\n\n"
                }
            }
            text += words.joined(separator: " ")
            pending = endsWithSpace ? .space : .none
        }

        /// Two line breaks in a row (`<br><br>`) separate paragraphs.
        mutating func breakLine() {
            pending = pending == .line ? .paragraph : max(pending, .line)
        }

        mutating func breakParagraph() {
            pending = .paragraph
        }
    }
}
