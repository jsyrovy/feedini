import Foundation

/// An article from a feed, with only what the feed itself says about it.
struct Article: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    var feedID: Feed.ID
    /// Identifies the article within its feed: the guid / Atom id, or the link when there is none.
    var key: String
    var title: String
    var link: URL?
    /// The date the feed gives, if any.
    var published: Date?
    var author: String?
    /// Plain text from the feed (paragraphs separated by blank lines).
    var text: String
    /// Primary language code (`cs`, `en`, …): the feed's language, or detected from the text.
    var language: String?
    /// When Feedini first saw the article.
    var firstSeen: Date
    /// When the article was read; `nil` while unread.
    var readAt: Date?
    /// The text of the source page, loaded on the user's request (P / T); `nil` until then.
    var pageText: String?
    /// The AI summary of the source page (T).
    var pageSummary: PageSummary?
    /// When the article was saved for later (S); `nil` while it isn't saved.
    var savedAt: Date?

    init(
        id: UUID = UUID(), feedID: Feed.ID, key: String, title: String, link: URL? = nil, published: Date? = nil,
        author: String? = nil, text: String = "", language: String? = nil, firstSeen: Date, readAt: Date? = nil,
        pageText: String? = nil, pageSummary: PageSummary? = nil, savedAt: Date? = nil
    ) {
        self.id = id
        self.feedID = feedID
        self.key = key
        self.title = title
        self.link = link
        self.published = published
        self.author = author
        self.text = text
        self.language = language
        self.firstSeen = firstSeen
        self.readAt = readAt
        self.pageText = pageText
        self.pageSummary = pageSummary
        self.savedAt = savedAt
    }

    var isRead: Bool { readAt != nil }
    var isSaved: Bool { savedAt != nil }

    /// The date used for ordering and retention: the published date, but never later than when the article was first
    /// seen (feeds sometimes give future dates), and the first sighting when the feed gives no date.
    var date: Date {
        guard let published else { return firstSeen }
        return min(published, firstSeen)
    }
}

/// What the AI wrote about an article's source page: the gist, and for longer texts the details.
struct PageSummary: Codable, Sendable, Hashable {
    /// One or two sentences.
    var tldr: String
    /// Short points that add to the TL;DR; empty for short texts.
    var details: [String]
    /// The language code it was written in.
    var language: String
    var date: Date
}
