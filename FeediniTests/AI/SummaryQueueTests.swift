import Foundation
import Testing

@testable import Feedini

@MainActor
struct SummaryQueueTests {
    private let tech = Feed.stub("Tech")
    private let news = Feed.stub("News")
    private let sleeper = ManualSleeper()
    private let status = AIStatus()

    /// Answers summaries for every story of the payload and translates topics by adding " (cs)".
    private static let answer: @Sendable (FakeCommandRunner.Call) -> FakeCommandRunner.Reply = { call in
        if let topics = call.payload["topics"] as? [[String: Any]], call.payload["stories"] == nil {
            let items = topics.compactMap { $0["id"] as? String }.map {
                #"{"id":"\#($0)","name":"Topic \#($0) (cs)","description":"Popis."}"#
            }
            return .structured(#"{"topics":[\#(items.joined(separator: ","))]}"#)
        }
        let ids = (call.payload["stories"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        let items = ids.map { #"{"story_id":"\#($0)","title":"Titulek \#($0)","summary":"Shrnutí."}"# }
        return .structured(#"{"summaries":[\#(items.joined(separator: ","))]}"#)
    }

    /// `count` unread two-article stories.
    private func library(stories count: Int, topics: [Topic] = []) -> Library {
        var articles: [Article] = []
        var stories: [Story] = []
        for index in 0..<count {
            let a = Article.stub("A\(index)", feed: tech.id, hours: -Double(index))
            let b = Article.stub("B\(index)", feed: news.id, hours: -Double(index))
            articles += [a, b]
            stories.append(Story(title: "Story \(index)", articleIDs: [a.id, b.id]))
        }
        return Library(feeds: [tech, news], articles: articles, stories: stories, topics: topics)
    }

    private func queue(
        _ host: TestLibraryHost, runner: FakeCommandRunner, found: Bool = true, enabled: Bool = true
    ) -> SummaryQueue {
        let locator = ClaudeLocator(homeDirectory: "/Users/me", searchPath: nil) { _ in found }
        return SummaryQueue(
            host: host, runner: runner, locator: locator, status: status,
            configuration: { AIConfiguration(isEnabled: enabled, languageCode: "cs") }, sleep: sleeper.sleep(for:))
    }

    @Test func summarizesInParallelBatches() async {
        let host = TestLibraryHost(library(stories: 25))
        let runner = FakeCommandRunner(handler: Self.answer)
        let queue = queue(host, runner: runner)

        queue.trigger()
        #expect(status.summarizing.count == 25)
        #expect(status.message == "Summarizing 25 stories…")
        #expect(queue.isRunning)
        await queue.waitUntilIdle()

        let sizes = runner.calls.map { ($0.payload["stories"] as? [Any])?.count ?? 0 }
        #expect(sizes.sorted() == [5, 10, 10])
        #expect(runner.calls.allSatisfy { $0.value(of: "--model") == "claude-haiku-5-5" })
        #expect(runner.calls.first?.payload["output_language"] as? String == "Czech")
        #expect(host.library.stories.values.allSatisfy { $0.summary?.language == "cs" })
        #expect(SummaryStep.pending(in: host.library, language: "cs").isEmpty)
        #expect(status.summarizing.isEmpty)
        #expect(status.calls.count == 3)
    }

    @Test func translatesTopicsInOneCall() async throws {
        let topic = Topic(name: "Games", description: "Games.", language: "en")
        let host = TestLibraryHost(library(stories: 1, topics: [topic]))
        let runner = FakeCommandRunner(handler: Self.answer)
        let queue = queue(host, runner: runner)

        queue.trigger()
        await queue.waitUntilIdle()

        #expect(runner.calls.count { $0.value(of: "--system-prompt") == Prompts.translateTopics } == 1)
        #expect(host.library.topics[topic.id]?.name == "Topic t1 (cs)")
        #expect(host.library.topics[topic.id]?.language == "cs")
        #expect(runner.calls.count == 2)
    }

    @Test func doesNothingWhenOffOrWithoutWork() async {
        let host = TestLibraryHost(library(stories: 2))
        let runner = FakeCommandRunner(handler: Self.answer)
        let off = queue(host, runner: runner, enabled: false)
        off.trigger()
        await off.waitUntilIdle()
        #expect(runner.calls.isEmpty)

        let emptyHost = TestLibraryHost(Library())
        let empty = queue(emptyHost, runner: runner)
        empty.trigger()
        #expect(!empty.isRunning)
    }

    @Test func stopsWithoutClaude() async {
        let host = TestLibraryHost(library(stories: 2))
        let runner = FakeCommandRunner(handler: Self.answer)
        let queue = queue(host, runner: runner, found: false)

        queue.trigger()
        await queue.waitUntilIdle()

        #expect(status.state == .unavailable("claude not found"))
        #expect(runner.calls.isEmpty)
        #expect(status.summarizing.isEmpty)
    }

    @Test func retriesAndGivesUpAfterRepeatedFailures() async throws {
        let host = TestLibraryHost(library(stories: 1))
        let runner = FakeCommandRunner([.error(.timedOut(.seconds(120)))])
        let queue = queue(host, runner: runner)
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        queue.trigger()
        for _ in 0..<SummaryQueue.maxAttempts {
            #expect(await sleeps.next() == SummaryQueue.retryDelay)
            sleeper.wake()
        }
        await queue.waitUntilIdle()

        #expect(runner.calls.count == 3)
        let story = try #require(host.library.stories.keys.first)
        #expect(status.summaryErrors[story] == "claude didn't answer in time")
        #expect(host.library.stories[story]?.summary == nil)

        // The next refresh tries again.
        queue.trigger(retryingFailed: true)
        #expect(status.summaryErrors.isEmpty)
        _ = await sleeps.next()
        #expect(runner.calls.count == 4)
        queue.cancel()
        await queue.waitUntilIdle()
    }

    @Test func storiesTheAnswerLeavesOutAreTriedAgain() async {
        let host = TestLibraryHost(library(stories: 1))
        let runner = FakeCommandRunner([
            .structured(#"{"summaries":[]}"#),
            .structured(#"{"summaries":[{"story_id":"s1","title":"T","summary":"S"}]}"#),
        ])
        let queue = queue(host, runner: runner)

        queue.trigger()
        await queue.waitUntilIdle()

        #expect(runner.calls.count == 2)
        #expect(host.library.stories.values.first?.summary?.title == "T")
    }
}
