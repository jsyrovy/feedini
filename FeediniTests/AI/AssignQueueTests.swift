import Foundation
import Testing

@testable import Feedini

@MainActor
struct AssignQueueTests {
    private let feed = Feed.stub("Tech")
    private let sleeper = ManualSleeper()
    private let status = AIStatus()

    /// Puts every new article of the payload into a story of its own, in a new topic.
    private static let ownStories: @Sendable (FakeCommandRunner.Call) -> FakeCommandRunner.Reply = { call in
        let articles = (call.payload["new_articles"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let stories = articles.map { #"{"title":"Story \#($0)","topic":"n1","article_ids":["\#($0)"]}"# }
        return .structured(
            #"{"attach":[],"new_topics":[{"key":"n1","name":"News","description":"All news."}],"new_stories":[\#(stories.joined(separator: ","))]}"#
        )
    }

    private func articles(_ count: Int) -> [Article] {
        (0..<count).map { Article.stub("Article \($0)", feed: feed.id, hours: -Double($0)) }
    }

    private func queue(
        _ host: TestLibraryHost, runner: FakeCommandRunner, configuration: AIConfiguration = AIConfiguration(),
        found: Bool = true
    ) -> AssignQueue {
        let locator = ClaudeLocator.stub(found: found)
        return AssignQueue(
            host: host, runner: runner, locator: locator, status: status, configuration: { configuration },
            sleep: sleeper.sleep(for:), now: { referenceDate })
    }

    @Test func organizesPendingArticlesInBatchesNewestFirst() async throws {
        let articles = articles(35)
        let host = TestLibraryHost(Library(feeds: [feed], articles: articles))
        let runner = FakeCommandRunner(handler: Self.ownStories)
        let queue = queue(host, runner: runner, configuration: AIConfiguration(languageCode: "cs"))
        var batchesApplied = 0
        queue.onBatchApplied = { batchesApplied += 1 }

        queue.trigger()
        await queue.waitUntilIdle()

        let batches = runner.calls.map { ($0.payload["new_articles"] as? [[String: Any]])?.count }
        #expect(batches == [10, 20, 5])
        let first = try #require(runner.calls.first)
        #expect(first.value(of: "--model") == "claude-haiku-5-5")
        #expect(first.value(of: "--effort") == "low")
        #expect(first.payload["output_language"] as? String == "Czech")
        let firstTitles = (first.payload["new_articles"] as? [[String: Any]])?.compactMap { $0["title"] as? String }
        #expect(firstTitles == (0..<10).map { "Article \($0)" })
        // The second batch sees the stories and the topic of the first.
        #expect((runner.calls[1].payload["stories"] as? [Any])?.count == 10)
        #expect((runner.calls[1].payload["topics"] as? [Any])?.count == 1)
        #expect(host.library.stories.count == 35)
        #expect(host.library.topics.count == 1)
        #expect(batchesApplied == 3)
        #expect(AssignQueue.pending(in: host.library, now: referenceDate).isEmpty)
        #expect(status.state == .idle)
        #expect(status.calls.count == 3)
        #expect(status.calls.first?.stats?.costUSD == 0.001)
        #expect(host.library.usage.map(\.calls) == [3])
        #expect(!queue.isRunning)
    }

    @Test func pendingArticlesAreUnreadOnesAndRecentReadOnesWithoutAStory() {
        let unreadOld = Article.stub("Unread old", feed: feed.id, hours: -500)
        let readRecent = Article.stub("Read recent", feed: feed.id, hours: -5, read: true)
        let readOld = Article.stub("Read old", feed: feed.id, hours: -100, read: true)
        let assigned = Article.stub("Assigned", feed: feed.id, hours: -1)
        let deferred = Article.stub("Deferred", feed: feed.id, hours: -2)
        let library = Library(
            feeds: [feed], articles: [unreadOld, readRecent, readOld, assigned, deferred],
            stories: [Story(title: "S", articleIDs: [assigned.id])])

        #expect(
            AssignQueue.pending(in: library, excluding: [deferred.id], now: referenceDate) == [
                readRecent.id, unreadOld.id,
            ])
    }

    @Test func doesNothingWhenAIIsOff() async {
        let host = TestLibraryHost(Library(feeds: [feed], articles: articles(3)))
        let runner = FakeCommandRunner(handler: Self.ownStories)
        let queue = queue(host, runner: runner, configuration: AIConfiguration(isEnabled: false))

        queue.trigger()
        await queue.waitUntilIdle()

        #expect(runner.calls.isEmpty)
        #expect(status.state == .off)
        #expect(host.library.stories.isEmpty)
    }

    @Test func stopsWithoutClaudeAndStartsAgainOnTheNextTrigger() async {
        let host = TestLibraryHost(Library(feeds: [feed], articles: articles(3)))
        let runner = FakeCommandRunner(handler: Self.ownStories)
        let missing = queue(host, runner: runner, found: false)

        missing.trigger()
        await missing.waitUntilIdle()

        #expect(runner.calls.isEmpty)
        #expect(status.state == .unavailable("claude not found"))
        #expect(status.message == "AI unavailable: claude not found")
        #expect(status.calls.first?.error == "claude not found")

        let found = queue(host, runner: runner)
        found.trigger()
        await found.waitUntilIdle()
        #expect(host.library.stories.count == 3)
        #expect(status.state == .idle)
    }

    @Test func retriesAFailingCallWithABackoff() async {
        let host = TestLibraryHost(Library(feeds: [feed], articles: articles(2)))
        let failing = FakeCommandRunner.Reply.stdout(#"{"type":"result","is_error":true,"result":"Overloaded"}"#)
        // The last answer leaves the articles out: they get stories of their own.
        let runner = FakeCommandRunner([
            failing, failing, .structured(#"{"attach":[],"new_topics":[],"new_stories":[]}"#),
        ])
        let queue = queue(host, runner: runner)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        queue.trigger()
        #expect(await sleeps.next() == .seconds(10))
        #expect(status.state == .organizing(2))
        sleeper.wake()
        #expect(await sleeps.next() == .seconds(60))
        sleeper.wake()
        await queue.waitUntilIdle()

        #expect(runner.calls.count == 3)
        #expect(status.calls.map(\.error) == [nil, "Overloaded", "Overloaded"])
        #expect(host.library.stories.count == 2)
    }

    @Test func defersABatchAfterRepeatedFailuresUntilTheNextRefresh() async {
        let host = TestLibraryHost(Library(feeds: [feed], articles: articles(2)))
        let runner = FakeCommandRunner([.error(.timedOut(.seconds(120)))])
        let queue = queue(host, runner: runner)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        queue.trigger()
        _ = await sleeps.next()
        sleeper.wake()
        _ = await sleeps.next()
        sleeper.wake()
        await queue.waitUntilIdle()

        #expect(runner.calls.count == 3)
        #expect(status.state == .unavailable("claude didn't answer in time"))
        // A trigger without retrying leaves the deferred articles alone.
        queue.trigger()
        await queue.waitUntilIdle()
        #expect(runner.calls.count == 3)

        queue.trigger(retryingFailed: true)
        _ = await sleeps.next()
        #expect(runner.calls.count == 4)
        queue.cancel()
        await queue.waitUntilIdle()
        #expect(!queue.isRunning)
    }

    @Test func statusKeepsTheLatestCalls() {
        for index in 0..<25 {
            status.record(AIStatus.Call(date: .hours(Double(index)), step: "Organize", error: "\(index)"))
        }
        #expect(status.calls.count == AIStatus.keptCalls)
        #expect(status.calls.first?.error == "24")
        #expect(AIStatus().message == nil)
        status.set(.organizing(1))
        #expect(status.message == "Organizing 1 article…")
        status.set(.organizing(12))
        #expect(status.message == "Organizing 12 articles…")
    }
}
