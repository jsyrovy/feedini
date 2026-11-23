import Foundation
import Testing

@testable import Feedini

struct StableIDTests {
    private let tech = URL(string: "https://example.com/tech.xml")!

    @Test func theSameAddressGivesTheSameFeedID() {
        #expect(StableID.feed(url: tech) == StableID.feed(url: tech))
        #expect(StableID.feed(url: tech) == StableID.feed(url: URL(string: "HTTPS://Example.COM/tech.xml/")!))
        #expect(StableID.feed(url: tech) != StableID.feed(url: URL(string: "https://example.com/Tech.xml")!))
        #expect(Feed(title: "Tech", url: tech).id == StableID.feed(url: tech))
    }

    @Test func theSameFeedAndKeyGiveTheSameArticleID() {
        let feed = StableID.feed(url: tech)
        let other = StableID.feed(url: URL(string: "https://example.com/news.xml")!)
        #expect(StableID.article(feed: feed, key: "a") == StableID.article(feed: feed, key: "a"))
        #expect(StableID.article(feed: feed, key: "a") != StableID.article(feed: feed, key: "b"))
        #expect(StableID.article(feed: feed, key: "a") != StableID.article(feed: other, key: "a"))
        #expect(StableID.feed(url: tech) != StableID.article(feed: feed, key: FeedSubscriber.normalizedAddress(tech)))
        let article = Article(feedID: feed, key: "a", title: "A", firstSeen: referenceDate)
        #expect(article.id == StableID.article(feed: feed, key: "a"))
    }

    @Test func aSavedLinkHasTheIDOfItsAddress() {
        var library = Library()
        let url = URL(string: "https://example.com/essay")!

        let id = library.saveLink(url, at: referenceDate).articleID

        #expect(id == StableID.article(feed: SavedLink.feedID, key: SavedLink.key(of: url)))
    }

    @Test func isAVersion8UUID() {
        let id = StableID.article(feed: StableID.feed(url: tech), key: "a")
        #expect(id.uuid.6 >> 4 == 8)
        #expect(id.uuid.8 >> 6 == 0b10)
        // Fixed across versions: stored libraries and the other device rely on it.
        #expect(StableID.feed(url: tech).uuidString == "E2E8CE45-173E-8F46-822E-72604EF94204")
    }
}
