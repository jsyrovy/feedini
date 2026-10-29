import Foundation
import Testing

@testable import Feedini

@MainActor
struct DebugCommandsTests {
    private let model = AppModel(
        preferences: Preferences(defaults: UserDefaults(suiteName: "feedini-tests-\(UUID().uuidString)")!),
        store: LibraryStore(
            fileURL: FileManager.default.temporaryDirectory.appending(path: "feedini-debug-\(UUID().uuidString).json")))

    @Test func addsFakeArticlesToOneDebugFeed() {
        model.debugAddFakeArticles()
        model.debugAddFakeArticles()

        #expect(model.library.feeds.map(\.title) == ["Debug"])
        #expect(model.library.articles.count == 14)
        #expect(Set(model.library.articles.values.map(\.key)).count == 14)
        #expect(model.library.articles.values.contains { $0.language == "cs" })
    }

    @Test func reorganizingForgetsStoriesAndTopicsAndRewritingForgetsSummaries() {
        let feed = Feed.stub()
        let article = Article.stub(feed: feed.id)
        let topic = Topic(name: "T", description: "")
        let story = Story(
            title: "S", topicID: topic.id, articleIDs: [article.id],
            summary: Summary(title: "T", text: "X", language: "cs", articleIDs: [article.id]))
        model.update { $0 = Library(feeds: [feed], articles: [article], stories: [story], topics: [topic]) }

        model.debugRewriteSummaries()
        #expect(model.library.stories[story.id]?.summary == nil)

        model.debugReorganize()
        #expect(model.library.stories.isEmpty)
        #expect(model.library.topics.isEmpty)
        #expect(model.library.articles.count == 1)
    }
}
