import Foundation
import Testing

@testable import Feedini

/// Answers are inline JSON in the shape of GitHub's release object, cut down to a few of its fields.
struct LatestReleaseTests {
    private static let answer = Data(
        """
        {"url":"https://api.github.com/repos/jsyrovy/feedini/releases/1",\
        "html_url":"https://github.com/jsyrovy/feedini/releases/tag/v0.4",\
        "tag_name":"v0.4","name":"0.4","draft":false,"prerelease":false,"assets":[]}
        """.utf8)

    private static func response(_ status: Int) -> HTTPURLResponse {
        HTTPURLResponse(url: LatestRelease.apiURL, statusCode: status, httpVersion: "HTTP/1.1", headerFields: nil)!
    }

    @Test func readsTheVersionAndThePage() async throws {
        let release = try await LatestRelease.fetch { _ in
            (Self.answer, Self.response(200))
        }
        #expect(release.version == AppVersion("0.4"))
        #expect(release.pageURL == URL(string: "https://github.com/jsyrovy/feedini/releases/tag/v0.4"))
    }

    @Test func asksGitHubsAPIForTheLatestRelease() {
        let request = LatestRelease.request()
        #expect(request.url == URL(string: "https://api.github.com/repos/jsyrovy/feedini/releases/latest"))
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == FeedFetcher.userAgent)
        #expect(request.timeoutInterval == LatestRelease.timeout)
    }

    @Test func otherStatusIsAFailure() async {
        await #expect(throws: UpdateError.status(403)) {
            try await LatestRelease.fetch { _ in
                (Data(#"{"message":"rate limit"}"#.utf8), Self.response(403))
            }
        }
    }

    @Test func tagThatIsNotAVersionIsAFailure() async {
        let answer = Data(
            #"{"tag_name":"nightly","html_url":"https://github.com/jsyrovy/feedini/releases/tag/nightly"}"#.utf8)
        await #expect(throws: UpdateError.invalidAnswer(reason: "the tag nightly is not a version")) {
            try await LatestRelease.fetch { _ in (answer, Self.response(200)) }
        }
    }

    @Test func unreadableAnswerIsAFailure() async {
        await #expect {
            try await LatestRelease.fetch { _ in (Data("<html>".utf8), Self.response(200)) }
        } throws: { error in
            guard case .invalidAnswer = error as? UpdateError else { return false }
            return true
        }
    }

    @Test func answerThatIsNotHTTPIsAFailure() async {
        let response = URLResponse(
            url: LatestRelease.apiURL, mimeType: nil, expectedContentLength: 0, textEncodingName: nil)
        await #expect(throws: UpdateError.invalidAnswer(reason: "not HTTP")) {
            try await LatestRelease.fetch { _ in (Self.answer, response) }
        }
    }

    @Test func noConnectionIsAFailure() async {
        let error = URLError(.notConnectedToInternet)
        await #expect(throws: UpdateError.connectionFailed(reason: error.localizedDescription)) {
            try await LatestRelease.fetch { _ in throw error }
        }
    }

    @Test(arguments: [URLError(.cancelled), CancellationError()] as [any Error])
    func cancelledRequestIsACancellation(error: any Error) async {
        await #expect(throws: CancellationError.self) {
            try await LatestRelease.fetch { _ in throw error }
        }
    }

    @Test func errorsSayWhatHappened() {
        #expect(UpdateError.connectionFailed(reason: "Offline.").description == "GitHub could not be reached: Offline.")
        #expect(UpdateError.status(429).description == "GitHub answered with HTTP 429")
        #expect(UpdateError.invalidAnswer(reason: "not HTTP").description == "Unexpected answer from GitHub: not HTTP")
    }
}
