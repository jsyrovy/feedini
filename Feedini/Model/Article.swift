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

    init(
        id: UUID = UUID(), feedID: Feed.ID, key: String, title: String, link: URL? = nil, published: Date? = nil,
        author: String? = nil, text: String = "", language: String? = nil, firstSeen: Date, readAt: Date? = nil
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
    }

    var isRead: Bool { readAt != nil }

    /// The date used for ordering and retention: the published date, but never later than when the article was first
    /// seen (feeds sometimes give future dates), and the first sighting when the feed gives no date.
    var date: Date {
        guard let published else { return firstSeen }
        return min(published, firstSeen)
    }
}
