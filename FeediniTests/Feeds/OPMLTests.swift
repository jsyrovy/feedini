import Foundation
import Testing

@testable import Feedini

struct OPMLTests {
    @Test func readsNestedOutlinesWithoutDuplicates() throws {
        let entries = try OPML.parse(Fixture.data("subscriptions.opml"))

        #expect(
            entries == [
                OPML.Entry(
                    title: "Example Tech Daily", feedURL: "https://tech.example.com/rss/",
                    siteURL: "https://tech.example.com/", folder: "Tech"),
                OPML.Entry(title: "Mac News", feedURL: "http://macnews.example.com/feed", folder: "Tech"),
                OPML.Entry(
                    title: "https://blog.example.org/feed.atom", feedURL: "https://blog.example.org/feed.atom"),
            ])
    }

    @Test func aFeedTakesTheNearestNamedCategoryAsItsFolder() throws {
        let opml = """
            <opml version="2.0"><body>
              <outline text="News">
                <outline text="World">
                  <outline text="Deep" xmlUrl="https://example.com/deep"/>
                </outline>
                <outline text=" ">
                  <outline text="Unnamed" xmlUrl="https://example.com/unnamed"/>
                </outline>
                <outline text="Direct" xmlUrl="https://example.com/direct"><outline text="Odd child"/></outline>
                <outline text="After" xmlUrl="https://example.com/after"/>
              </outline>
              <outline text="Top" xmlUrl="https://example.com/top"/>
            </body></opml>
            """

        let entries = try OPML.parse(Data(opml.utf8))

        #expect(entries.map(\.title) == ["Deep", "Unnamed", "Direct", "After", "Top"])
        #expect(entries.map(\.folder) == ["World", "News", "News", "News", nil])
    }

    @Test func rejectsOtherDocuments() throws {
        #expect(throws: OPML.ParseError.notOPML) { try OPML.parse(Fixture.data("rss2.xml")) }
        #expect {
            try OPML.parse(Data("<opml><body><outline".utf8))
        } throws: { error in
            if case OPML.ParseError.invalid = error { true } else { false }
        }
        #expect {
            try OPML.parse(Data("garbage".utf8))
        } throws: { error in
            if case OPML.ParseError.invalid = error { true } else { false }
        }
    }

    @Test func exportsFeedsThatImportBack() throws {
        let feeds = [
            Feed(
                title: "Tom & Jerry \"<News>\"", url: URL(string: "https://example.com/feed?a=1&b=2")!,
                siteURL: URL(string: "https://example.com/")),
            Feed(title: "Second\nline", url: URL(string: "https://example.org/rss")!),
        ]

        let data = OPML.export(feeds)
        let entries = try OPML.parse(data)

        #expect(
            entries == [
                OPML.Entry(
                    title: "Tom & Jerry \"<News>\"", feedURL: "https://example.com/feed?a=1&b=2",
                    siteURL: "https://example.com/"),
                OPML.Entry(title: "Second\nline", feedURL: "https://example.org/rss", siteURL: nil),
            ])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.hasPrefix("<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<opml version=\"2.0\">"))
        #expect(text.contains("<title>Feedini subscriptions</title>"))
    }

    @Test func exportsFoldersAsCategoriesInTheirOrder() throws {
        let work = Folder(name: "Work & Co")
        let daily = Folder(name: "Daily")
        let empty = Folder(name: "Empty")
        let feeds = [
            Feed.stub("Loose"),
            Feed.stub("Paper", folder: daily.id),
            Feed.stub("Tracker", folder: work.id),
            Feed.stub("Gone", folder: UUID()),
            Feed.stub("Radio", folder: daily.id),
        ]

        let data = OPML.export(feeds, folders: [work, daily, empty])
        let entries = try OPML.parse(data)

        #expect(entries.map(\.title) == ["Tracker", "Paper", "Radio", "Loose", "Gone"])
        #expect(entries.map(\.folder) == ["Work & Co", "Daily", "Daily", nil, nil])
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(!text.contains("Empty"))
    }
}
