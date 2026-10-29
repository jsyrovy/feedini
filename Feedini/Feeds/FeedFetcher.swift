import Foundation

/// What to download, with the validators of the previous download.
struct FetchRequest: Sendable, Equatable {
    var feedID: Feed.ID
    var url: URL
    var etag: String?
    var lastModified: String?
}

enum FetchOutcome: Sendable, Equatable {
    case fetched(FetchedFeed)
    /// The feed is unchanged since the previous download (HTTP 304).
    case notModified
    case failed(FetchError)
}

struct FetchedFeed: Sendable, Equatable {
    var data: Data
    var etag: String?
    var lastModified: String?
}

enum FetchError: Error, Sendable, Equatable {
    case http(status: Int)
    /// App Transport Security blocked a plain HTTP address, typically a redirect from HTTPS to HTTP.
    case insecureConnection
    case timedOut
    case hostNotFound
    case offline
    case secureConnectionFailed
    case tooLarge
    case other(String)

    /// For the user, in the feed list.
    var message: String {
        switch self {
        case .http(let status):
            "The server answered with HTTP \(status) (\(HTTPURLResponse.localizedString(forStatusCode: status)))."
        case .insecureConnection:
            "The feed redirects to an insecure (HTTP) address. Only HTTPS feeds are supported."
        case .timedOut: "The server didn't respond in time."
        case .hostNotFound: "The server couldn't be found."
        case .offline: "The Mac is offline."
        case .secureConnectionFailed: "A secure connection to the server couldn't be made."
        case .tooLarge: "The feed is larger than \(FeedFetcher.maxFeedSize / 1_000_000) MB."
        case .other(let description): description
        }
    }

    init(_ error: any Error) {
        guard let error = error as? URLError else {
            self = .other(error.localizedDescription)
            return
        }
        switch error.code {
        case .appTransportSecurityRequiresSecureConnection: self = .insecureConnection
        case .timedOut: self = .timedOut
        case .cannotFindHost, .dnsLookupFailed: self = .hostNotFound
        case .notConnectedToInternet, .networkConnectionLost, .dataNotAllowed: self = .offline
        case .secureConnectionFailed, .serverCertificateUntrusted, .serverCertificateHasBadDate,
            .serverCertificateNotYetValid, .serverCertificateHasUnknownRoot, .clientCertificateRejected:
            self = .secureConnectionFailed
        default: self = .other(error.localizedDescription)
        }
    }
}

/// Downloads feeds over HTTPS with conditional GET (ETag / Last-Modified), a timeout and no cache of its own.
/// Redirects are followed by `URLSession`; App Transport Security blocks any to plain HTTP.
struct FeedFetcher: Sendable {
    static let userAgent = "Feedini/1.0 (+https://github.com/jsyrovy/feedini)"
    static let maxFeedSize = 20_000_000
    /// Downloads running at once in `fetchAll`.
    static let maxConcurrentDownloads = 6

    let session: URLSession

    init(session: URLSession = FeedFetcher.makeSession()) {
        self.session = session
    }

    /// A session for feeds; tests pass a configuration with stubbed protocols.
    static func makeSession(_ configuration: URLSessionConfiguration = .ephemeral) -> URLSession {
        configuration.timeoutIntervalForRequest = 20
        configuration.timeoutIntervalForResource = 60
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.httpShouldSetCookies = false
        configuration.httpAdditionalHeaders = [
            "User-Agent": userAgent,
            "Accept": "application/rss+xml, application/atom+xml, application/xml;q=0.9, text/xml;q=0.9, */*;q=0.8",
        ]
        return URLSession(configuration: configuration)
    }

    func fetch(_ request: FetchRequest) async -> FetchOutcome {
        var urlRequest = URLRequest(url: request.url)
        if let etag = request.etag {
            urlRequest.setValue(etag, forHTTPHeaderField: "If-None-Match")
        }
        if let lastModified = request.lastModified {
            urlRequest.setValue(lastModified, forHTTPHeaderField: "If-Modified-Since")
        }
        do {
            let (data, response) = try await session.data(for: urlRequest)
            guard let http = response as? HTTPURLResponse else {
                return .failed(.other("The server's response isn't HTTP."))
            }
            switch http.statusCode {
            case 304:
                return .notModified
            case 200..<300:
                guard data.count <= Self.maxFeedSize else { return .failed(.tooLarge) }
                return .fetched(
                    FetchedFeed(
                        data: data, etag: http.value(forHTTPHeaderField: "ETag"),
                        lastModified: http.value(forHTTPHeaderField: "Last-Modified")))
            default:
                return .failed(.http(status: http.statusCode))
            }
        } catch {
            return .failed(FetchError(error))
        }
    }

    /// Downloads all feeds, `maxConcurrentDownloads` at a time; a failing feed never affects the others.
    func fetchAll(_ requests: [FetchRequest]) async -> [Feed.ID: FetchOutcome] {
        let outcomes = await requests.concurrentMap(limit: Self.maxConcurrentDownloads) { await fetch($0) }
        return Dictionary(zip(requests.map(\.feedID), outcomes), uniquingKeysWith: { _, last in last })
    }
}
