import Foundation
import Testing

@testable import Feedini

@MainActor
struct MacServicesTests {
    private let extractor = FakePageExtractor()
    private let services: MacServices
    private var model: AppModel { services.model }

    init() {
        services = MacServices.test(
            runner: FakeCommandRunner([.structured(#"{"status":"ok","tldr":"The gist."}"#)]), extractor: extractor)
    }

    @Test func savingALinkWithAIPreparesItsSummary() async throws {
        let id = try model.saveLink("example.com/essay").articleID
        #expect(model.pageStatus[id] == PageStatus.Work(phase: .loading, summary: true))
        await model.pageLoader.waitUntilIdle()

        #expect(model.library.pageTextIDs == [id])
        #expect(model.library.articles[id]?.pageSummary?.tldr == "The gist.")
    }

    @Test func savingALinkWithoutAIOnlyLoadsItsText() async throws {
        services.preferences.aiEnabled = false
        let id = try model.saveLink("example.com/essay").articleID
        await model.pageLoader.waitUntilIdle()

        #expect(model.library.pageTextIDs == [id])
        #expect(model.library.articles[id]?.pageSummary == nil)
        // Without saying that AI is off.
        #expect(model.pageStatus.pages.isEmpty)
    }

    @Test func reloadingASavedLinkLoadsItsPageAgain() async throws {
        services.preferences.aiEnabled = false
        let id = try model.saveLink("example.com/essay").articleID
        await model.pageLoader.waitUntilIdle()

        model.pageOpened(id)
        services.reloadPage(id)
        await model.pageLoader.waitUntilIdle()

        #expect(extractor.requests.count == 2)
        #expect(model.library.pageTextIDs == [id])
    }

    @Test func theSummarySettingsGoIntoTheLibraryOnceItIsLoaded() async {
        services.preferences.summaryLanguage = "de"
        #expect(model.library.summarySettings == nil)
        #expect(model.summarySettings == SummarySettings())

        await services.start()
        #expect(model.summarySettings == SummarySettings(language: "de", singleArticles: .never))

        services.preferences.singleArticleSummaries = .always
        #expect(model.library.summarySettings == SummarySettings(language: "de", singleArticles: .always))
    }

    @Test func theAIOrganizesNewArticlesOnlyOnceTheModelIsLoaded() async {
        let runner = FakeCommandRunner([.structured(#"{"attach":[],"new_topics":[],"new_stories":[]}"#)])
        let services = MacServices.test(runner: runner)
        let feed = Feed.stub("Tech")
        services.model.update { $0 = Library(feeds: [feed], articles: [Article.stub(feed: feed.id)]) }
        services.model.organize()
        #expect(!services.assignQueue.isRunning)

        services.organize(retryingFailed: false)
        await services.assignQueue.waitUntilIdle()
        #expect(runner.calls.count == 1)
    }

    @Test func aiTurnedOffSaysSo() {
        #expect(services.aiStatus.state == .idle)
        let preferences = MacPreferences.test()
        preferences.aiEnabled = false
        #expect(MacServices(preferences: preferences, store: .temporary()).aiStatus.state == .off)
    }

    @Test func backUpNowNeedsFeeds() {
        #expect(!services.canBackUpNow)
        let feed = Feed.stub("Tech")
        model.update { $0 = Library(feeds: [feed]) }
        #expect(services.canBackUpNow)
    }

    @Test func syncIsOffByDefaultAndSaysWhyItCantRunInThisBuild() async {
        let directory = FileManager.default.temporaryDirectory.appending(path: "feedini-sync-\(UUID().uuidString)")
        let services = MacServices(
            preferences: .test(), store: .temporary(),
            syncStateStore: SyncStateStore(fileURL: directory.appending(path: "sync.json")))
        await services.start()
        #expect(services.sync.status == .off)
        #expect(!services.preferences.syncsWithICloud)

        // The test host is signed ad hoc, without the iCloud entitlement.
        services.preferences.syncsWithICloud = true
        await services.syncSettingTask?.value
        #expect(services.sync.status == .unavailable(SyncAvailability.notInThisBuild))
        #expect(!services.sync.isRunning)

        services.preferences.syncsWithICloud = false
        await services.syncSettingTask?.value
        #expect(services.sync.status == .off)
    }
}
