import Foundation
import Testing

@testable import Feedini

@MainActor
struct SyncControllerTests {
    typealias F = SyncRecord.Field

    private let model = AppModel.test()
    private let engine = FakeSyncEngine()
    private let stateURL = FileManager.default.temporaryDirectory.appending(
        path: "feedini-sync-\(UUID().uuidString).json")
    private let controller: SyncController
    private let feed = Feed.stub("Tech")
    private let article: Article

    init() {
        controller = SyncController(model: model, stateStore: SyncStateStore(fileURL: stateURL), now: { referenceDate })
        article = Article.stub(feed: feed.id, key: "a")
        model.update { [feed, article] in $0 = Library(feeds: [feed], articles: [article]) }
    }

    /// Started, with the first fetch (and its merge) done and the library uploaded.
    private func started() async {
        await controller.start { _ in engine }
        controller.willFetch()
        controller.didFetch()
        var saved: [(id: SyncRecord.ID, systemFields: Data)] = []
        for id in engine.pending.saves.keys {
            _ = await controller.recordToSend(id)
            saved.append((id, systemFields(id)))
        }
        controller.sent(saved: saved, deleted: [], conflicts: [], missing: [], failures: [])
        engine.clear()
    }

    private func systemFields(_ id: SyncRecord.ID) -> Data { Data(id.name.utf8) }

    @Test func theFirstFetchMergesAndUploadsTheLibrary() async {
        await controller.start { _ in engine }
        #expect(model.sync === controller)
        #expect(engine.fetches == 1)
        #expect(!controller.allowsRetention)

        controller.willFetch()
        #expect(controller.status == .syncing)
        var zoneArticle = article
        zoneArticle.readAt = .hours(-1)
        await controller.fetched(
            [FetchedRecord(record: SyncRecord(article: zoneArticle), systemFields: systemFields(.article(article.id)))],
            deletions: [])
        #expect(model.library.articles[article.id]?.readAt == .hours(-1))
        controller.didFetch()

        #expect(controller.allowsRetention)
        #expect(!controller.state.needsMerge)
        // The zone has the article as the merge left it: only what it doesn't have goes up.
        #expect(Set(engine.pending.saves.keys) == [.feed(feed.id), .meta])
        #expect(controller.status == .synced(referenceDate))
    }

    @Test func localChangesAreSentAndThoseFromTheZoneAreNot() async throws {
        await started()

        model.markRead([article.id])
        #expect(engine.pending.saves == [.article(article.id): [F.readAt]])
        engine.clear()

        let other = Article.stub("Other", feed: feed.id, key: "b")
        await controller.fetched(
            [FetchedRecord(record: SyncRecord(article: other), systemFields: systemFields(.article(other.id)))],
            deletions: [])
        #expect(model.library.articles[other.id] != nil)
        #expect(engine.pending.isEmpty)

        try await model.storePageText("The page.", for: article.id)
        #expect(engine.pending.saves == [.pageText(article.id): [F.text]])
    }

    @Test func sendsTheChangedFieldsOverTheZonesRecordAndForgetsThemOnceSaved() async throws {
        await started()
        let id = SyncRecord.ID.article(article.id)
        // Not in the zone yet: every field.
        let new = Article.stub("New", feed: feed.id, key: "n")
        model.update { $0.articles[new.id] = new }
        #expect(await controller.recordToSend(.article(new.id))?.fields == SyncRecord.articleFields)
        controller.sent(
            saved: [(.article(new.id), Data())], deleted: [], conflicts: [], missing: [], failures: [])
        #expect(controller.state.changedFields(of: .article(new.id)).isEmpty)

        model.setSaved(article.id, at: .hours(1))
        let toSend = try #require(await controller.recordToSend(id))
        #expect(toSend.fields == [F.savedAt])
        #expect(toSend.systemFields == systemFields(id))
        #expect(toSend.record.date(F.savedAt) == .hours(1))
        // Read while it was being sent: that goes out next time.
        model.markRead([article.id])
        controller.sent(saved: [(id, systemFields(id))], deleted: [], conflicts: [], missing: [], failures: [])
        #expect(controller.state.changedFields(of: id) == [F.readAt])

        model.update { $0.articles[article.id] = nil }
        #expect(await controller.recordToSend(id) == nil)
        controller.sent(saved: [], deleted: [id], conflicts: [], missing: [], failures: [])
        #expect(controller.state.systemFields[id.name] == nil)
    }

    @Test func aPageTextIsSentWithItsTextAndComesIntoAFile() async throws {
        await started()
        try await model.storePageText("The page.", for: article.id)
        #expect(await controller.recordToSend(.pageText(article.id))?.record.pageText == "The page.")

        let other = Article.stub("Other", feed: feed.id, key: "b")
        model.update { $0.articles[other.id] = other }
        await controller.fetched(
            [
                FetchedRecord(
                    record: SyncRecord(pageText: "From the iPhone.", of: other.id),
                    systemFields: systemFields(.pageText(other.id)))
            ], deletions: [])
        #expect(await model.pageText(other.id) == "From the iPhone.")
        #expect(engine.pending.saves[.pageText(other.id)] == nil)
    }

    @Test func aConflictKeepsTheZonesContentAndSendsTheReadingAgain() async throws {
        await started()
        let id = SyncRecord.ID.article(article.id)
        model.markRead([article.id])
        _ = await controller.recordToSend(id)
        var zone = article
        zone.title = "Downloaded on the iPhone"
        zone.savedAt = .hours(2)
        engine.clear()

        controller.sent(
            saved: [], deleted: [],
            conflicts: [FetchedRecord(record: SyncRecord(article: zone), systemFields: Data([9]))],
            missing: [], failures: [])

        let local = try #require(model.library.articles[article.id])
        #expect(local.title == "Downloaded on the iPhone")
        #expect(local.savedAt == .hours(2))
        #expect(local.isRead)
        #expect(engine.pending.saves == [id: [F.readAt]])
        #expect(controller.state.systemFields[id.name] == Data([9]))
        // A page text in conflict is just sent again.
        controller.sent(
            saved: [], deleted: [],
            conflicts: [FetchedRecord(record: SyncRecord(pageText: "X", of: article.id), systemFields: Data())],
            missing: [], failures: [])
        #expect(engine.pending.saves[.pageText(article.id)] == [F.text])
    }

    @Test func aRecordDeletedElsewhereIsCreatedAgainWhenUnreadElseGoesHereToo() async {
        await started()
        let read = Article.stub("Read", feed: feed.id, key: "r", read: true)
        model.update { $0.articles[read.id] = read }
        engine.clear()

        controller.sent(
            saved: [], deleted: [], conflicts: [], missing: [.article(article.id), .article(read.id)], failures: [])

        #expect(engine.pending.saves == [.article(article.id): SyncRecord.articleFields])
        #expect(model.library.articles[read.id] == nil)
        #expect(model.library.articles[article.id] != nil)
    }

    @Test func deletionsFromTheZoneAndFailures() async {
        await started()
        await controller.fetched([], deletions: [.feed(feed.id)])
        #expect(model.library.feeds.isEmpty)

        controller.sent(
            saved: [], deleted: [], conflicts: [], missing: [], failures: [(.feed(feed.id), "Quota exceeded")])
        #expect(controller.status == .failed("Quota exceeded"))
        #expect(controller.status.problem == "Quota exceeded")

        engine.fails = true
        await controller.send()
        #expect(controller.status == .failed("The network is down."))
        await controller.fetch()
        #expect(engine.fetches == 2)
    }

    @Test func aZoneOfANewerVersionStopsSyncing() async {
        await started()
        await controller.fetched(
            [FetchedRecord(record: SyncRecord(minimumVersion: SyncSchema.version + 1), systemFields: Data())],
            deletions: [])

        #expect(controller.status == .needsUpdate)
        #expect(controller.status.problem == SyncSchema.updateMessage)
        #expect(!controller.isRunning)
        #expect(engine.isCancelled)
        #expect(model.sync == nil)
        // Its state stays for when Feedini is updated.
        #expect(FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test func remembersItsStateAcrossStarts() async {
        await started()
        controller.stateChanged(Data([1, 2, 3]))
        await controller.stop(forgetting: false)
        #expect(controller.status == .off)
        model.markRead([article.id])

        let again = SyncController(model: model, stateStore: SyncStateStore(fileURL: stateURL))
        var loaded: SyncState?
        await again.start { state in
            loaded = state
            return FakeSyncEngine()
        }

        #expect(loaded?.engine == Data([1, 2, 3]))
        #expect(loaded?.needsMerge == false)
        #expect(again.status == .synced(referenceDate))
    }

    @Test func signingOutStopsAndForgetsAnotherAccountMergesAgain() async {
        await started()
        await controller.accountChanged(.switchAccounts)
        #expect(controller.isRunning)
        #expect(controller.state.needsMerge)

        await controller.accountChanged(.signOut)
        #expect(controller.status == .unavailable(SyncController.signedOutMessage))
        #expect(!controller.isRunning)
        #expect(!FileManager.default.fileExists(atPath: stateURL.path))
    }

    @Test func aDeletedZoneTurnsSyncOffAndAResetUploadsEverything() async {
        await started()
        await controller.zoneDeleted(encryptedDataReset: true)
        #expect(engine.pending.saves.keys.contains(.article(article.id)))

        var turnedOff = false
        controller.onTurnedOff = { turnedOff = true }
        await controller.zoneDeleted(encryptedDataReset: false)
        #expect(turnedOff)
        #expect(!controller.isRunning)
        #expect(controller.status == .failed(SyncController.deletedMessage))
    }

    @Test func deletingTheICloudDataStopsAndKeepsTheLibrary() async throws {
        await started()
        try await controller.deleteICloudData()
        #expect(engine.deletedZone)
        #expect(!controller.isRunning)
        #expect(model.library.articles.count == 1)
        // Nothing to do while stopped.
        model.markRead([article.id])
        await controller.fetch()
        await controller.send()
        controller.didFetch()
        await controller.fetched([], deletions: [.feed(feed.id)])
        controller.sent(saved: [], deleted: [], conflicts: [], missing: [], failures: [])
        #expect(model.library.feeds.count == 1)
    }

    @Test func retentionWaitsWhileAFetchIsApplied() async {
        await started()
        controller.willFetch()
        #expect(!controller.allowsRetention)
        controller.didFetch()
        #expect(controller.allowsRetention)
        #expect(SyncStatus.off.problem == nil)
    }

    @Test func articlesReadOnTheOtherDeviceStayInTheList() async {
        await started()
        let session = ReadingSession(model: model)
        var read = article
        read.readAt = .hours(1)

        await controller.fetched(
            [FetchedRecord(record: SyncRecord(article: read), systemFields: Data())], deletions: [])

        #expect(session.keptArticles == [article.id])
        #expect(session.entries.map(\.id) == [.loose(article.id)])
    }
}
