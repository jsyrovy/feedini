import Foundation

@testable import Feedini

/// Records what the sync controller asks of CloudKit; fetching and sending do nothing unless told to fail.
@MainActor
final class FakeSyncEngine: SyncEngining {
    struct Failure: Error, LocalizedError {
        var errorDescription: String? { "The network is down." }
    }

    private(set) var pending = SyncChanges()
    private(set) var fetches = 0
    private(set) var sends = 0
    private(set) var deletedZone = false
    private(set) var isCancelled = false
    var fails = false

    func enqueue(_ changes: SyncChanges) {
        pending.add(changes)
    }

    func fetchChanges() async throws {
        fetches += 1
        if fails { throw Failure() }
    }

    func sendChanges() async throws {
        sends += 1
        if fails { throw Failure() }
    }

    func deleteZone() async throws {
        if fails { throw Failure() }
        deletedZone = true
    }

    func cancel() {
        isCancelled = true
    }

    func clear() {
        pending = SyncChanges()
    }
}
