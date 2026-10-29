import Foundation
import Synchronization

@testable import Feedini

/// Answers requests of a session made by `StubURLProtocol.session()` with canned replies, keyed by URL. Tests use
/// URLs with unique hosts, so tests running in parallel never share a reply.
final class StubURLProtocol: URLProtocol, @unchecked Sendable {
    enum Reply: Sendable {
        case response(status: Int, headers: [String: String] = [:], body: Data = Data())
        case redirect(to: URL, status: Int = 301)
        case failure(URLError.Code)

        static func feed(_ fixture: String, headers: [String: String] = [:]) throws -> Reply {
            .response(status: 200, headers: headers, body: try Fixture.data(fixture))
        }
    }

    private struct Route {
        var reply: Reply
        var delay: Duration
    }

    private static let routes = Mutex<[URL: Route]>([:])
    private static let recorded = Mutex<[URLRequest]>([])
    private static let inFlight = Mutex<(now: Int, max: Int)>((0, 0))

    static func session() -> URLSession {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        return FeedFetcher.makeSession(configuration)
    }

    static func stub(_ url: URL, _ reply: Reply, delay: Duration = .zero) {
        routes.withLock { $0[url] = Route(reply: reply, delay: delay) }
    }

    /// Requests made to the host, in order.
    static func requests(to host: String) -> [URLRequest] {
        recorded.withLock { $0.filter { $0.url?.host() == host } }
    }

    /// The most requests that were ever loading at the same time (across all tests using delays).
    static var maxInFlight: Int {
        inFlight.withLock { $0.max }
    }

    /// A unique `https://<uuid>.test/<path>` URL.
    static func uniqueURL(_ path: String = "feed.xml") -> URL {
        URL(string: "https://\(UUID().uuidString.lowercased()).test/\(path)")!
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let request = self.request
        Self.recorded.withLock { $0.append(request) }
        guard let url = request.url, let route = Self.routes.withLock({ $0[url] }) else {
            client?.urlProtocol(self, didFailWithError: URLError(.cannotFindHost))
            return
        }
        guard route.delay > .zero else {
            reply(route.reply, to: request)
            return
        }
        Self.inFlight.withLock { state in
            state.now += 1
            state.max = max(state.max, state.now)
        }
        let seconds = Double(route.delay.components.attoseconds) / 1e18 + Double(route.delay.components.seconds)
        DispatchQueue.global().asyncAfter(deadline: .now() + seconds) { [self] in
            Self.inFlight.withLock { $0.now -= 1 }
            reply(route.reply, to: request)
        }
    }

    override func stopLoading() {}

    private func reply(_ reply: Reply, to request: URLRequest) {
        guard let url = request.url else { return }
        switch reply {
        case .response(let status, let headers, let body):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: headers)!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case .redirect(let target, let status):
            let response = HTTPURLResponse(
                url: url, statusCode: status, httpVersion: "HTTP/1.1", headerFields: ["Location": target.absoluteString]
            )!
            client?.urlProtocol(self, wasRedirectedTo: URLRequest(url: target), redirectResponse: response)
        case .failure(let code):
            client?.urlProtocol(self, didFailWithError: URLError(code))
        }
    }
}
