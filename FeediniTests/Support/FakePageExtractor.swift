import Foundation

@testable import Feedini

/// A `PageExtracting` without WebKit: answers every page with `result(url)` and records the requests.
@MainActor
final class FakePageExtractor: PageExtracting {
    var result: (URL) -> Result<String, PageError> = { url in
        .success("Text of the page \(url.lastPathComponent).")
    }
    private(set) var requests: [URL] = []
    /// The most extractions that ran at the same time.
    private(set) var maxRunning = 0
    private var running = 0

    func extract(_ url: URL) async throws(PageError) -> String {
        requests.append(url)
        running += 1
        maxRunning = max(maxRunning, running)
        defer { running -= 1 }
        await Task.yield()
        return try result(url).get()
    }
}
