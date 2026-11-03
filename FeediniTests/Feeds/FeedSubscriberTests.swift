import Foundation
import Testing

@testable import Feedini

struct FeedSubscriberTests {
    private let subscriber = FeedSubscriber(fetcher: FeedFetcher(session: StubURLProtocol.session()))

    /// The `http://` address of an `https://` URL.
    private func httpVariant(of url: URL) -> String {
        "http://" + url.absoluteString.dropFirst("https://".count)
    }

    @Test func turnsWhatTheUserTypedIntoAnHTTPSAddress() {
        #expect(
            FeedSubscriber.httpsURL(for: "https://example.com/feed")! == (
                URL(string: "https://example.com/feed")!, false
            ))
        #expect(FeedSubscriber.httpsURL(for: "  example.com/rss ")! == (URL(string: "https://example.com/rss")!, false))
        #expect(FeedSubscriber.httpsURL(for: "HTTP://example.com/a")! == (URL(string: "https://example.com/a")!, true))
        #expect(FeedSubscriber.httpsURL(for: "feed://example.com/a")! == (URL(string: "https://example.com/a")!, false))
        #expect(
            FeedSubscriber.httpsURL(for: "localhost:8080/feed")! == (URL(string: "https://localhost:8080/feed")!, false)
        )
        #expect(FeedSubscriber.httpsURL(for: "") == nil)
        #expect(FeedSubscriber.httpsURL(for: "ftp://example.com/feed") == nil)
        #expect(FeedSubscriber.httpsURL(for: "not an address") == nil)
        #expect(FeedSubscriber.httpsURL(for: "nodot") == nil)
    }

    @Test func comparesFeedAddresses() {
        #expect(
            FeedSubscriber.isSame(URL(string: "https://Example.com/feed/")!, URL(string: "https://example.com/feed")!))
        #expect(!FeedSubscriber.isSame(URL(string: "https://example.com/a")!, URL(string: "https://example.com/b")!))
    }

    @Test func subscribesToAFeed() async throws {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, try .feed("rss2.xml", headers: ["ETag": "\"1\""]))

        let result = await subscriber.subscribe(url.absoluteString, existing: [])

        let subscription = try result.get()
        #expect(subscription.url == url)
        #expect(subscription.title == "Example Tech Daily")
        #expect(subscription.etag == "\"1\"")
        #expect(subscription.parsed.items.count == 3)
    }

    @Test func usesTheHostForAFeedWithoutATitle() throws {
        let subscription = FeedSubscriber.Subscription(
            url: URL(string: "https://untitled.example.com/feed")!, parsed: ParsedFeed(items: []))
        #expect(subscription.title == "untitled.example.com")
    }

    @Test func triesHTTPSForAnHTTPAddress() async throws {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, try .feed("atom.xml"))
        let http = httpVariant(of: url)

        #expect(try await subscriber.subscribe(http, existing: []).get().url == url)
    }

    @Test func rejectsAnHTTPFeedThatDoesntWorkOverHTTPS() async {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, .response(status: 404))
        let http = httpVariant(of: url)

        let result = await subscriber.subscribe(http, existing: [])

        let failure = FeedSubscriber.Failure.notHTTPS("The server answered with HTTP 404 (not found).")
        #expect(result == .failure(failure))
        #expect(
            failure.message
                == "Over HTTPS: The server answered with HTTP 404 (not found). Only HTTPS feeds are supported.")
    }

    @Test func doesntRepeatTheHTTPSRuleForAnHTTPFeedRedirectingToHTTP() async {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, .failure(.appTransportSecurityRequiresSecureConnection))
        let http = httpVariant(of: url)

        let result = await subscriber.subscribe(http, existing: [])

        #expect(result == .failure(.unreachable(FetchError.insecureConnection.message)))
    }

    @Test func rejectsWebPagesUnreachableAddressesAndDuplicates() async throws {
        let page = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(page, try .feed("not-a-feed.html"))
        let missing = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(missing, .response(status: 404))
        let unchanged = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(unchanged, .response(status: 304))
        let httpPage = httpVariant(of: page)

        #expect(
            await subscriber.subscribe(page.absoluteString, existing: [])
                == .failure(.notAFeed("This isn't an RSS or Atom feed.")))
        #expect(
            await subscriber.subscribe(httpPage, existing: []) == .failure(.notHTTPS("This isn't an RSS or Atom feed."))
        )
        #expect(
            await subscriber.subscribe(missing.absoluteString, existing: [])
                == .failure(.unreachable("The server answered with HTTP 404 (not found).")))
        #expect(await subscriber.subscribe(unchanged.absoluteString, existing: []) != .failure(.alreadySubscribed))
        #expect(await subscriber.subscribe("nonsense", existing: []) == .failure(.invalidAddress))
        #expect(
            await subscriber.subscribe(page.absoluteString + "/", existing: [page]) == .failure(.alreadySubscribed))
        #expect(FeedSubscriber.Failure.invalidAddress.message == "This isn't a web address.")
        #expect(FeedSubscriber.Failure.alreadySubscribed.message == "You already follow this feed.")
    }

    @Test func importsOPMLEntriesInOrderAndExplainsTheSkippedOnes() async throws {
        let first = StubURLProtocol.uniqueURL()
        let broken = StubURLProtocol.uniqueURL()
        let second = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(first, try .feed("rss2.xml"), delay: .milliseconds(50))
        StubURLProtocol.stub(broken, .response(status: 500))
        StubURLProtocol.stub(second, try .feed("atom.xml"))
        let entries = [
            OPML.Entry(title: "First", feedURL: first.absoluteString),
            OPML.Entry(title: "Broken", feedURL: broken.absoluteString),
            OPML.Entry(title: "Second", feedURL: second.absoluteString),
            OPML.Entry(title: "First over HTTP", feedURL: httpVariant(of: first)),
            OPML.Entry(title: "Known", feedURL: "https://known.example.com/feed"),
        ]

        let result = await subscriber.subscribe(entries, existing: [URL(string: "https://known.example.com/feed")!])

        #expect(result.added.map(\.url) == [first, second])
        #expect(result.skipped.map(\.entry.title) == ["Broken", "First over HTTP", "Known"])
        #expect(
            result.skipped.map(\.failure) == [
                .unreachable("The server answered with HTTP 500 (internal server error)."), .alreadySubscribed,
                .alreadySubscribed,
            ])
        #expect(
            result.errorReport == """
                Feedini OPML import: 2 added, 2 already followed, 1 failed.

                Broken
                Feed: \(broken.absoluteString)
                Error: The server answered with HTTP 500 (internal server error).
                """)
    }

    @Test func reportsTheErrorsOfAnImportWithTheSiteAndFolder() {
        let entry = { (title: String) in
            OPML.Entry(
                title: title, feedURL: "https://\(title).example.com/feed", siteURL: "https://\(title).example.com",
                folder: "Blogs")
        }
        var result = FeedSubscriber.ImportResult()
        result.skipped = [(entry("known"), .alreadySubscribed)]
        #expect(result.errorReport == nil)

        result.skipped += [(entry("gone"), .unreachable("Not found.")), (entry("page"), .notAFeed("Not a feed."))]
        #expect(
            result.errorReport == """
                Feedini OPML import: 0 added, 1 already followed, 2 failed.

                gone
                Feed: https://gone.example.com/feed
                Site: https://gone.example.com
                Folder: Blogs
                Error: Not found.

                page
                Feed: https://page.example.com/feed
                Site: https://page.example.com
                Folder: Blogs
                Error: Not a feed.
                """)
    }

    @Test func checksMoreEntriesThanRunAtOnceAndKeepsTheirOrder() async throws {
        let entries = (0..<(FeedFetcher.maxConcurrentDownloads + 3)).map { index in
            let url = StubURLProtocol.uniqueURL()
            StubURLProtocol.stub(url, .response(status: 404), delay: .milliseconds(20))
            return OPML.Entry(title: "Feed \(index)", feedURL: url.absoluteString)
        }

        let result = await subscriber.subscribe(entries, existing: [])

        #expect(result.added.isEmpty)
        #expect(result.skipped.map(\.entry) == entries)
    }
}
