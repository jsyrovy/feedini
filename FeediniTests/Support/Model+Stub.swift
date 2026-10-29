import Foundation

@testable import Feedini

/// A fixed point in time for tests: 2026-10-29 12:00:00 UTC.
let referenceDate = Date(timeIntervalSince1970: 1_793_275_200)

extension Date {
    /// `referenceDate` moved by the given number of hours.
    static func hours(_ hours: Double) -> Date {
        referenceDate.addingTimeInterval(hours * 60 * 60)
    }
}

extension Feed {
    static func stub(_ title: String = "Feed", id: UUID = UUID(), lastSuccess: Date? = nil) -> Feed {
        Feed(
            id: id, title: title, url: URL(string: "https://example.com/\(title.lowercased()).xml")!,
            lastSuccess: lastSuccess)
    }
}

extension Article {
    /// An article first seen and published at `date` (hours from `referenceDate`).
    static func stub(
        _ title: String = "Article", feed: Feed.ID, id: UUID = UUID(), key: String? = nil, hours: Double = 0,
        read: Bool = false
    ) -> Article {
        Article(
            id: id, feedID: feed, key: key ?? "https://example.com/\(id.uuidString)", title: title,
            link: URL(string: "https://example.com/\(id.uuidString)"), published: .hours(hours),
            text: "Text of \(title).", firstSeen: .hours(hours), readAt: read ? .hours(hours) : nil)
    }
}

extension Library {
    /// A library with the given feeds, articles and stories.
    init(feeds: [Feed], articles: [Article], stories: [Story] = [], topics: [Topic] = []) {
        self.init()
        self.feeds = feeds
        self.articles = Dictionary(uniqueKeysWithValues: articles.map { ($0.id, $0) })
        self.stories = Dictionary(uniqueKeysWithValues: stories.map { ($0.id, $0) })
        self.topics = Dictionary(uniqueKeysWithValues: topics.map { ($0.id, $0) })
    }
}
