import Foundation
import Testing

@testable import Feedini

struct SyncStateStoreTests {
    private let directory = FileManager.default.temporaryDirectory.appending(
        path: "feedini-sync-\(UUID().uuidString)", directoryHint: .isDirectory)
    private var fileURL: URL { directory.appending(path: "sync.json") }
    private let sleeper = ManualSleeper()

    private func store() -> SyncStateStore {
        SyncStateStore(fileURL: fileURL, debounce: .seconds(2), sleep: sleeper.sleep(for:))
    }

    @Test func startsWithAMergeAndKeepsWhatItSaved() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = store()
        #expect(await store.load() == SyncState())
        #expect(SyncState().needsMerge)
        var state = SyncState(engine: Data([1, 2]), systemFields: ["feed-x": Data([3])], needsMerge: false)
        state.lastSync = referenceDate
        var sleeps = sleeper.sleeps.makeAsyncIterator()

        await store.save(SyncState())
        #expect(await sleeps.next() == .seconds(2))
        // The latest state during the delay is written.
        await store.save(state)
        sleeper.wake()
        await store.flush()

        #expect(await SyncStateStore(fileURL: fileURL).load() == state)
    }

    @Test func aStateThatCantBeReadStartsOverAndDeletingForgetsIt() async throws {
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("{".utf8).write(to: fileURL)
        let store = store()
        #expect(await store.load() == SyncState())

        await store.save(SyncState(needsMerge: false))
        await store.delete()
        await store.flush()
        await store.delete()

        #expect(!FileManager.default.fileExists(atPath: fileURL.path))
    }

    @Test func remembersTheFieldsToSendUntilTheRecordIsDeleted() {
        let id = SyncRecord.ID.article(UUID())
        var state = SyncState()

        state.add(SyncChanges(saves: [id: [SyncRecord.Field.readAt]]))
        state.add(SyncChanges(saves: [id: [SyncRecord.Field.savedAt]]))
        #expect(state.changedFields(of: id) == [SyncRecord.Field.readAt, SyncRecord.Field.savedAt])

        state.add(SyncChanges(deletes: [id]))
        #expect(state.changedFields(of: id).isEmpty)
    }

    @Test func liesNextToTheLibrary() {
        #expect(
            SyncStateStore.defaultFileURL.deletingLastPathComponent()
                == LibraryStore.defaultFileURL.deletingLastPathComponent())
    }
}
