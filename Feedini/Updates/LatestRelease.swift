import Foundation

enum UpdateError: Error, Equatable, Sendable, CustomStringConvertible {
    /// No answer: offline, a timeout, DNS, TLS, …
    case connectionFailed(reason: String)
    /// GitHub answered with another status than 200 (403 or 429 when its rate limit is reached).
    case status(Int)
    case invalidAnswer(reason: String)

    var description: String {
        switch self {
        case .connectionFailed(let reason): "GitHub could not be reached: \(reason)"
        case .status(let code): "GitHub answered with HTTP \(code)"
        case .invalidAnswer(let reason): "Unexpected answer from GitHub: \(reason)"
        }
    }
}

/// The latest published release of Feedini on GitHub: neither a draft (`make publish` leaves one) nor a prerelease,
/// so the app offers what the Homebrew cask offers.
struct LatestRelease: Equatable, Sendable {
    static let apiURL = URL(string: "https://api.github.com/repos/jsyrovy/feedini/releases/latest")!
    static let timeout: TimeInterval = 15

    let version: AppVersion
    /// The release's page on GitHub, with the notes and the zip.
    let pageURL: URL

    /// Gets one answer to a request, off the main actor; replaced in tests.
    typealias Transport = @Sendable (URLRequest) async throws -> (Data, URLResponse)

    /// A session that keeps no cookies, cache or credentials on disk.
    static let urlSession = URLSession(configuration: .ephemeral)

    static func request() -> URLRequest {
        var request = URLRequest(url: apiURL, timeoutInterval: timeout)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        // GitHub refuses requests without a user agent.
        request.setValue(FeedFetcher.userAgent, forHTTPHeaderField: "User-Agent")
        return request
    }

    /// Asks GitHub for the latest release. Cancelling the calling task throws `CancellationError`.
    @concurrent
    static func fetch(transport: Transport = { try await urlSession.data(for: $0) }) async throws -> LatestRelease {
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await transport(request())
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            throw UpdateError.connectionFailed(reason: error.localizedDescription)
        }
        try Task.checkCancellation()
        return try parse(data, response: response)
    }

    static func parse(_ data: Data, response: URLResponse) throws(UpdateError) -> LatestRelease {
        guard let response = response as? HTTPURLResponse else {
            throw .invalidAnswer(reason: "not HTTP")
        }
        guard response.statusCode == 200 else {
            throw .status(response.statusCode)
        }
        let answer: Answer
        do {
            answer = try JSONDecoder().decode(Answer.self, from: data)
        } catch {
            throw .invalidAnswer(reason: "\(error)")
        }
        guard let version = AppVersion(answer.tagName) else {
            throw .invalidAnswer(reason: "the tag \(answer.tagName) is not a version")
        }
        return LatestRelease(version: version, pageURL: answer.htmlURL)
    }

    /// The fields Feedini reads of GitHub's release object.
    private struct Answer: Decodable {
        let tagName: String
        let htmlURL: URL

        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case htmlURL = "html_url"
        }
    }
}
