import Foundation
import Testing

@testable import Feedini

struct FeedParserTests {
    private func parse(_ fixture: String, baseURL: URL? = nil) throws -> ParsedFeed {
        try FeedParser.parse(Fixture.data(fixture), baseURL: baseURL)
    }

    private func date(_ iso: String) -> Date? {
        FeedParser.iso8601Date(iso)
    }

    @Test func parsesRSS2WithDublinCoreCreatorCDATAAndDuplicates() throws {
        let feed = try parse("rss2.xml", baseURL: URL(string: "https://tech.example.com/rss/"))

        #expect(feed.title == "Example Tech Daily")
        #expect(feed.siteURL == URL(string: "https://tech.example.com"))
        #expect(feed.language == "cs-CZ")
        #expect(
            feed.items.map(\.key) == [
                "1001-tech.example.com", "1002-tech.example.com",
                "https://tech.example.com/clanky/srovnani-tarifu/a-1003/",
            ])

        let first = feed.items[0]
        #expect(first.title == "Nový robotický vysavač umí vyjít schody")
        #expect(first.link == URL(string: "https://tech.example.com/clanky/vysavac-schody/a-1001/"))
        #expect(first.published == date("2026-10-29T10:45:00Z"))
        #expect(first.author == "Jana Nováková")
        #expect(first.text == "Výrobce ukázal vysavač, který zvládne schodiště – zatím jen v laboratoři.")

        let second = feed.items[1]
        #expect(second.title == "Banka spouští platby hodinkami")
        #expect(second.published == date("2026-10-29T07:30:00Z"))
        #expect(second.author == "Petr Svoboda")
        #expect(second.text == "První odstavec o platbách.\n\nDruhý odstavec.")

        // No guid and no date: keyed by the link, resolved against the feed URL; a double-escaped entity.
        let third = feed.items[2]
        #expect(third.title == "AT&T a T-Mobile: srovnání tarifů")
        #expect(third.published == nil)
        #expect(third.author == nil)
    }

    @Test func parsesRSS091WithHTMLInTheDescription() throws {
        let feed = try parse("rss091.xml")

        #expect(feed.title == "Example Trails - downhill magazine")
        #expect(feed.siteURL == URL(string: "http://www.trails.example.com"))
        #expect(feed.language == "cs")
        #expect(feed.items.count == 2)
        #expect(feed.items[0].key == "https://trails.example.com/clanek/1-spotcheck")
        #expect(feed.items[0].text == "Hned za hranicí je ráj pro bikery.")
        #expect(feed.items[0].published == date("2026-10-29T02:00:00Z"))
        #expect(feed.items[1].published == date("2026-10-29T03:00:00Z"))
    }

    @Test func parsesAtom() throws {
        let feed = try parse("atom.xml", baseURL: URL(string: "https://blog.example.org/feed.atom"))

        #expect(feed.title == "Example Engineering Blog")
        #expect(feed.siteURL == URL(string: "https://blog.example.org/"))
        #expect(feed.language == "en-US")
        #expect(feed.items.count == 3)

        let first = feed.items[0]
        #expect(first.key == "tag:blog.example.org,2026:posts/1")
        #expect(first.title == "Scaling the queue")
        #expect(first.link == URL(string: "https://blog.example.org/posts/scaling-the-queue"))
        #expect(first.published == date("2026-10-28T18:30:02Z"))
        #expect(first.author == "Alex Writer")
        #expect(first.text == "We moved the queue.\n\n• Faster\n• Cheaper")

        let second = feed.items[1]
        #expect(second.title == "Notes on 1 < 2")
        #expect(second.link == URL(string: "https://blog.example.org/posts/notes"))
        #expect(second.published == date("2026-10-27T09:00:00Z"))
        #expect(second.text == "Plain text with a <tag> that is not markup.")

        let third = feed.items[2]
        #expect(third.link == nil)
        #expect(third.published == date("2026-10-26T00:00:00Z"))
        #expect(third.text == "First bold paragraph.\n\nSecond.")
    }

    @Test func prefersTheFullContentAndCleansLongHTML() throws {
        let feed = try parse("rss2-content.xml")

        #expect(
            feed.items[0].text
                == "Example Corp announced a laptop today.\n\nIt has a touch display and a new chip.\n\n• 14-inch\n• 16-inch\n\nDiscuss this article in our forums"
        )
        #expect(
            feed.items[1].text == "Full text of the article, first paragraph.\n\nSecond paragraph with … an ellipsis.")
    }

    @Test func repairsHTMLEntitiesBareAmpersandsAndLeadingWhitespace() throws {
        let feed = try parse("html-entities.xml")

        #expect(feed.title == "Broken & Co")
        #expect(feed.items.count == 1)
        #expect(feed.items[0].title == "Tom & Jerry – Q&A …")
        #expect(feed.items[0].link == URL(string: "https://broken.example.com/1?a=1&b=2"))
        #expect(feed.items[0].text == "Price: 5 € &unknownentity; ž")
    }

    @Test func readsTheDeclaredEncoding() throws {
        let feed = try parse("windows-1250.xml")

        #expect(feed.title == "Příliš žluťoučký kůň")
        #expect(feed.items.first?.title == "Úpěl ďábelské ódy")
        #expect(feed.items.first?.text == "Šťastný řidič čekal.")
    }

    @Test func parsesRSS1() throws {
        let feed = try parse("rdf.xml")

        #expect(feed.title == "Example RDF Site")
        #expect(feed.language == "de")
        #expect(feed.items.first?.key == "https://rdf.example.net/1")
        #expect(feed.items.first?.published == date("2026-10-29T06:15:00Z"))
    }

    @Test func rejectsAWebPage() {
        #expect(throws: FeedParserError.notAFeed) { try parse("not-a-feed.html") }
    }

    @Test func rejectsOtherXML() {
        #expect(throws: FeedParserError.notAFeed) {
            try FeedParser.parse(Data("<?xml version=\"1.0\"?><svg><g/></svg>".utf8))
        }
    }

    @Test func rejectsGarbage() {
        #expect {
            try FeedParser.parse(Data("not xml at all".utf8))
        } throws: { error in
            if case FeedParserError.invalid = error { true } else { false }
        }
    }

    @Test func keepsTheItemsBeforeABreakInTheMiddle() throws {
        let xml = """
            <rss version="2.0"><channel><title>T</title>
            <item><title>One</title><guid>1</guid></item>
            <item><title>Two</title><guid>2</guid></item></chann
            """
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.items.map(\.key) == ["1", "2"])
    }

    @Test func usesTheTextForItemsWithoutATitleAndDropsItemsWithoutAnyKey() throws {
        let xml = """
            <rss version="2.0"><channel>
            <item><guid>1</guid><description>Only a description here.</description></item>
            <item><description>No guid, link or title.</description></item>
            <item><title>Unsafe link</title><link>javascript:alert(1)</link></item>
            </channel></rss>
            """
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.items.map(\.title) == ["Only a description here.", "Unsafe link"])
        #expect(feed.items[1].link == nil)
        #expect(feed.title == nil)
    }

    @Test func cutsVeryLongTexts() throws {
        let long = String(repeating: "word ", count: 5000)
        let xml =
            "<rss version=\"2.0\"><channel><item><guid>1</guid><description>\(long)</description></item></channel></rss>"
        let feed = try FeedParser.parse(Data(xml.utf8))
        #expect(feed.items[0].text.count == FeedParser.maxTextLength)
        #expect(feed.items[0].text.hasSuffix("word…"))
    }

    @Test func parsesDateVariants() {
        let expected = date("2026-10-29T10:45:00Z")
        #expect(FeedParser.rfc822Date("Thu, 29 Oct 2026 10:45:00 GMT") == expected)
        #expect(FeedParser.rfc822Date("Thu, 29 Oct 2026 11:45:00 +0100") == expected)
        #expect(FeedParser.rfc822Date("Thu, 29 Oct 2026 10:45 GMT") == expected)
        #expect(FeedParser.rfc822Date(" 29 Oct 2026 10:45:00 +0000 ") == expected)
        #expect(FeedParser.rfc822Date("Thu, 29 Oct 2026 10:45:00") == expected)
        #expect(FeedParser.rfc822Date("2026-10-29T10:45:00Z") == expected)
        #expect(FeedParser.rfc822Date("yesterday") == nil)
        #expect(FeedParser.iso8601Date("2026-10-29T12:45:00.500+02:00") == expected?.addingTimeInterval(0.5))
    }

    @Test func repairLeavesWellFormedReferencesAlone() {
        #expect(FeedParser.repairXML(Data("&amp;&lt;&#38;".utf8)) == Data("&amp;&lt;&#38;".utf8))
    }
}
