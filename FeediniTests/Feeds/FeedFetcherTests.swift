import Foundation
import Testing

@testable import Feedini

@Suite(.serialized)
struct FeedFetcherTests {
    private let fetcher = FeedFetcher(session: StubURLProtocol.session())

    private func request(_ url: URL, etag: String? = nil, lastModified: String? = nil) -> FetchRequest {
        FetchRequest(feedID: UUID(), url: url, etag: etag, lastModified: lastModified)
    }

    @Test func returnsTheBodyAndValidatorsWhateverTheContentType() async throws {
        let url = StubURLProtocol.uniqueURL()
        let body = try Fixture.data("rss091.xml")
        StubURLProtocol.stub(
            url,
            .response(
                status: 200,
                headers: [
                    "Content-Type": "text/html; charset=utf-8", "ETag": "W/\"abc\"",
                    "Last-Modified": "Thu, 29 Oct 2026 12:41:05 GMT",
                ], body: body))

        let outcome = await fetcher.fetch(request(url))

        #expect(
            outcome
                == .fetched(FetchedFeed(data: body, etag: "W/\"abc\"", lastModified: "Thu, 29 Oct 2026 12:41:05 GMT")))
        let sent = try #require(StubURLProtocol.requests(to: url.host()!).first)
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == nil)
        #expect(sent.value(forHTTPHeaderField: "If-Modified-Since") == nil)
    }

    @Test func sendsTheValidatorsAndUnderstandsNotModified() async throws {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, .response(status: 304))

        let outcome = await fetcher.fetch(request(url, etag: "\"v1\"", lastModified: "Wed, 28 Oct 2026 12:00:00 GMT"))

        #expect(outcome == .notModified)
        let sent = try #require(StubURLProtocol.requests(to: url.host()!).first)
        #expect(sent.value(forHTTPHeaderField: "If-None-Match") == "\"v1\"")
        #expect(sent.value(forHTTPHeaderField: "If-Modified-Since") == "Wed, 28 Oct 2026 12:00:00 GMT")
    }

    @Test func followsRedirects() async throws {
        let old = StubURLProtocol.uniqueURL("old.xml")
        let new = URL(string: "https://\(old.host()!)/new.xml")!
        StubURLProtocol.stub(old, .redirect(to: new))
        StubURLProtocol.stub(new, try .feed("atom.xml"))

        let outcome = await fetcher.fetch(request(old))

        #expect(outcome == .fetched(FetchedFeed(data: try Fixture.data("atom.xml"))))
    }

    @Test func reportsHTTPErrors() async {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, .response(status: 404))

        let outcome = await fetcher.fetch(request(url))

        #expect(outcome == .failed(.http(status: 404)))
        #expect(FetchError.http(status: 404).message == "The server answered with HTTP 404 (not found).")
    }

    @Test(arguments: [
        (URLError.Code.appTransportSecurityRequiresSecureConnection, FetchError.insecureConnection),
        (.timedOut, .timedOut),
        (.cannotFindHost, .hostNotFound),
        (.dnsLookupFailed, .hostNotFound),
        (.notConnectedToInternet, .offline),
        (.serverCertificateUntrusted, .secureConnectionFailed),
    ])
    func mapsNetworkErrors(code: URLError.Code, expected: FetchError) async {
        let url = StubURLProtocol.uniqueURL()
        StubURLProtocol.stub(url, .failure(code))

        #expect(await fetcher.fetch(request(url)) == .failed(expected))
    }

    @Test func explainsEveryError() {
        #expect(FetchError.insecureConnection.message.contains("Only HTTPS feeds are supported"))
        #expect(FetchError.tooLarge.message == "The feed is larger than 20 MB.")
        #expect(FetchError(URLError(.badServerResponse)) == .other(URLError(.badServerResponse).localizedDescription))
        #expect(FetchError(CocoaError(.fileNoSuchFile)) == .other(CocoaError(.fileNoSuchFile).localizedDescription))
        for error in [FetchError.timedOut, .hostNotFound, .offline, .secureConnectionFailed, .other("x")] {
            #expect(!error.message.isEmpty)
        }
    }

    @Test func fetchesManyFeedsConcurrentlyAndIsolatesFailures() async throws {
        let body = try Fixture.data("rss2.xml")
        let requests = (0..<10).map { index in
            let url = StubURLProtocol.uniqueURL()
            StubURLProtocol.stub(
                url, index == 3 ? .response(status: 500) : .response(status: 200, body: body),
                delay: .milliseconds(100))
            return request(url)
        }

        let outcomes = await fetcher.fetchAll(requests)

        #expect(outcomes.count == 10)
        for (index, request) in requests.enumerated() {
            #expect(
                outcomes[request.feedID]
                    == (index == 3 ? .failed(.http(status: 500)) : .fetched(FetchedFeed(data: body))))
        }
        #expect(StubURLProtocol.maxInFlight > 1)
        #expect(StubURLProtocol.maxInFlight <= FeedFetcher.maxConcurrentDownloads)
    }
}
