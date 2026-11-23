import Foundation
import Observation

/// What syncing is doing, for Settings and the menu bar.
enum SyncStatus: Equatable, Sendable {
    case off
    /// It can't run: no iCloud account, a build without the entitlement.
    case unavailable(String)
    case syncing
    /// Up to date since then (`nil`: nothing has worked yet since start).
    case synced(Date?)
    case failed(String)
    /// The zone needs a newer Feedini (`SyncSchema`).
    case needsUpdate

    /// Why it doesn't sync, for the user; `nil` when it does or is off.
    var problem: String? {
        switch self {
        case .unavailable(let reason), .failed(let reason): reason
        case .needsUpdate: SyncSchema.updateMessage
        case .off, .syncing, .synced: nil
        }
    }
}

/// What the controller asks of CloudKit (`CloudSyncEngine`, a thin `CKSyncEngine` wrapper); a fake in tests.
@MainActor
protocol SyncEngining: AnyObject {
    /// Adds records to save or delete; the engine asks for them when it sends (`SyncController.recordToSend`).
    func enqueue(_ changes: SyncChanges)
    func fetchChanges() async throws
    func sendChanges() async throws
    /// Deletes the zone with everything in it (Delete iCloud Data…).
    func deleteZone() async throws
    /// Stops; nothing more is fetched or sent.
    func cancel()
}

/// A record fetched from the zone with its system fields (`CKRecord.encodeSystemFields`).
struct FetchedRecord: Sendable {
    var record: SyncRecord
    var systemFields: Data
}

/// Keeps the library and the iCloud zone in step: sends the changes made here (`LibrarySync`), applies the zone's
/// (`SyncMerge`), resolves conflicts, keeps `SyncState`. The engine reports to it with records already turned into
/// `SyncRecord`s, so everything here runs on the main actor without CloudKit and is tested with a fake engine.
@MainActor
@Observable
final class SyncController: LibrarySync {
    private(set) var status = SyncStatus.off
    /// Called when syncing turned itself off (the zone was deleted elsewhere), with the reason; the platform turns
    /// its setting off.
    @ObservationIgnored var onTurnedOff: (@MainActor (String) -> Void)?

    @ObservationIgnored private unowned let model: AppModel
    @ObservationIgnored private let stateStore: SyncStateStore
    @ObservationIgnored private let now: @Sendable () -> Date
    @ObservationIgnored private(set) var state = SyncState()
    @ObservationIgnored private var engine: (any SyncEngining)?
    /// Makes an engine from a state (given at start; another iCloud account needs a new one).
    @ObservationIgnored private var makeEngine: ((SyncState) -> any SyncEngining)?
    @ObservationIgnored private var isFetching = false
    /// The fields of records being sent: only those are done once saved (a change meanwhile goes out next time).
    @ObservationIgnored private var sending: [SyncRecord.ID: Set<String>] = [:]
    /// The latest hand-over to the state store; each waits for the previous one, so saves keep their order.
    @ObservationIgnored private var persisting: Task<Void, Never>?

    static let deletedMessage = "The Feedini data in iCloud was deleted. Turn sync on to upload this library again."
    static let signedOutMessage = "Sign in to iCloud to sync."

    init(model: AppModel, stateStore: SyncStateStore = SyncStateStore(), now: @escaping @Sendable () -> Date = { .now })
    {
        self.model = model
        self.stateStore = stateStore
        self.now = now
    }

    var isRunning: Bool { engine != nil }

    /// Starts syncing with an engine made from the saved state; the first fetch merges the library with the zone's.
    func start(makeEngine: @escaping (SyncState) -> any SyncEngining) async {
        guard engine == nil else { return }
        self.makeEngine = makeEngine
        state = await stateStore.load()
        let engine = makeEngine(state)
        self.engine = engine
        model.sync = self
        status = .synced(state.lastSync)
        if state.needsMerge {
            Log.sync.info("Merging the library with iCloud")
        }
        await fetch()
    }

    /// Stops syncing; `forgetting` drops the sync state too (turned off, another account), so the next start merges.
    func stop(forgetting: Bool, status: SyncStatus = .off) async {
        engine?.cancel()
        engine = nil
        if model.sync === self {
            model.sync = nil
        }
        isFetching = false
        sending = [:]
        await persisting?.value
        if forgetting {
            state = SyncState()
            await stateStore.delete()
        } else {
            await stateStore.flush()
        }
        self.status = status
    }

    /// Delete iCloud Data…: deletes the zone, forgets the state and stops; the library stays.
    func deleteICloudData() async throws {
        try await engine?.deleteZone()
        await stop(forgetting: true)
        Log.sync.info("Deleted the iCloud data")
    }

    /// Fetches the zone's changes now.
    func fetch() async {
        guard let engine else { return }
        do {
            try await engine.fetchChanges()
        } catch {
            fail(error)
        }
    }

    /// Sends the pending changes now.
    func send() async {
        guard let engine else { return }
        do {
            try await engine.sendChanges()
        } catch {
            fail(error)
        }
    }

    // MARK: LibrarySync

    func libraryChanged(from old: Library, to new: Library) {
        enqueue(SyncChanges.diff(old: old, new: new))
    }

    func pageTextStored(_ id: Article.ID) {
        enqueue(SyncChanges(saves: [.pageText(id): [SyncRecord.Field.text]]))
    }

    func fetchBeforeRefresh() async {
        await fetch()
    }

    var allowsRetention: Bool { !isFetching && !state.needsMerge }

    // MARK: Events of the engine

    func willFetch() {
        isFetching = true
        status = .syncing
    }

    /// Applies fetched records and deletions: page texts go into files, the rest into the library at once.
    func fetched(_ records: [FetchedRecord], deletions: [SyncRecord.ID]) async {
        guard engine != nil else { return }
        if let meta = records.first(where: { $0.record.id == .meta }),
            !SyncSchema.supports(minimumVersion: meta.record.minimumVersion)
        {
            Log.sync.error("The iCloud data needs a newer Feedini")
            await stop(forgetting: false, status: .needsUpdate)
            return
        }
        for fetched in records {
            state.systemFields[fetched.record.id.name] = fetched.systemFields
        }
        var follow = SyncChanges()
        let mode: SyncMerge.Mode = state.needsMerge ? .merge : .update
        model.applyRemote { library in
            for fetched in records where fetched.record.id.kind != .pageText {
                let id = fetched.record.id
                follow.add(
                    SyncMerge.apply(fetched.record, to: &library, pending: state.changedFields(of: id), mode: mode))
            }
            for id in deletions {
                follow.add(SyncMerge.delete(id, from: &library))
            }
        }
        for id in deletions {
            state.systemFields[id.name] = nil
        }
        for fetched in records where fetched.record.id.kind == .pageText {
            guard let id = fetched.record.id.uuid, let text = fetched.record.pageText,
                state.changedFields(of: fetched.record.id).isEmpty
            else { continue }
            try? await model.storeSyncedPageText(text, for: id)
        }
        enqueue(follow)
        Log.sync.info("Fetched \(records.count) records and \(deletions.count) deletions")
    }

    /// A fetch ended: a pending merge is done, and the whole library goes up (records the zone has already are
    /// resolved as conflicts).
    func didFetch() {
        isFetching = false
        guard engine != nil else { return }
        if state.needsMerge {
            state.needsMerge = false
            enqueue(SyncMerge.everything(in: model.library))
        }
        succeeded()
    }

    /// The record to send for a pending change, the system fields of the zone's record and the fields to set
    /// (all for a record the zone doesn't have yet); `nil` when the library doesn't have it anymore.
    func recordToSend(_ id: SyncRecord.ID) async -> (record: SyncRecord, systemFields: Data?, fields: Set<String>)? {
        let pageText: String? =
            if id.kind == .pageText, let uuid = id.uuid { await model.pageText(uuid) } else { nil }
        guard let record = SyncRecord.make(id, from: model.library, pageText: pageText) else {
            state.changedFields[id.name] = nil
            return nil
        }
        let systemFields = state.systemFields[id.name]
        let changed = state.changedFields(of: id)
        let fields = systemFields == nil || changed.isEmpty ? SyncMerge.allFields(of: id.kind) : changed
        sending[id] = fields
        return (record, systemFields, fields)
    }

    /// The outcome of sending: saved records (with their new system fields), deleted ones, conflicts (the zone's
    /// newer record), records the other device deleted meanwhile, and other failures.
    func sent(
        saved: [(id: SyncRecord.ID, systemFields: Data)], deleted: [SyncRecord.ID], conflicts: [FetchedRecord],
        missing: [SyncRecord.ID], failures: [(id: SyncRecord.ID, message: String)]
    ) {
        guard engine != nil else { return }
        for (id, systemFields) in saved {
            state.systemFields[id.name] = systemFields
            let remaining = state.changedFields(of: id).subtracting(sending.removeValue(forKey: id) ?? [])
            state.changedFields[id.name] = remaining.isEmpty ? nil : remaining
        }
        for id in deleted {
            state.systemFields[id.name] = nil
            state.changedFields[id.name] = nil
        }
        var follow = SyncChanges()
        for conflict in conflicts {
            follow.add(resolve(conflict))
        }
        for id in missing {
            sending[id] = nil
            state.systemFields[id.name] = nil
            // Kept here (unread, saved, in use): created again; else the deletion wins here too.
            model.applyRemote { follow.add(SyncMerge.delete(id, from: &$0)) }
        }
        enqueue(follow)
        if let failure = failures.first {
            for (id, _) in failures {
                sending[id] = nil
            }
            Log.sync.error("Sending \(failure.id.name, privacy: .public) failed: \(failure.message, privacy: .public)")
            status = .failed(failure.message)
        } else {
            succeeded()
        }
    }

    /// The zone's record wins except for the fields changed here (`SyncMerge.resolve`); the result is applied here
    /// and sent again over the zone's record.
    private func resolve(_ conflict: FetchedRecord) -> SyncChanges {
        let id = conflict.record.id
        sending[id] = nil
        state.systemFields[id.name] = conflict.systemFields
        guard id.kind != .pageText else { return SyncChanges(saves: [id: [SyncRecord.Field.text]]) }
        let changed = state.changedFields(of: id)
        let local = SyncRecord.make(id, from: model.library) ?? conflict.record
        let resolved = SyncMerge.resolve(server: conflict.record, local: local, changed: changed)
        model.applyRemote { SyncMerge.apply(resolved, to: &$0) }
        let toSend = changed.subtracting(id.kind == .article ? SyncRecord.articleContentFields : [])
        state.changedFields[id.name] = toSend.isEmpty ? nil : toSend
        return toSend.isEmpty ? SyncChanges() : SyncChanges(saves: [id: toSend])
    }

    func stateChanged(_ serialization: Data) {
        state.engine = serialization
        persist()
    }

    /// The iCloud account changed: signed out, syncing stops (the library stays); another account starts over with
    /// a merge; signing in starts.
    enum AccountChange: Sendable {
        case signIn, signOut, switchAccounts
    }

    func accountChanged(_ change: AccountChange) async {
        guard let makeEngine else { return }
        switch change {
        case .signIn:
            if engine == nil {
                await start(makeEngine: makeEngine)
            }
        case .signOut:
            await stop(forgetting: true, status: .unavailable(Self.signedOutMessage))
        case .switchAccounts:
            await stop(forgetting: true)
            await start(makeEngine: makeEngine)
        }
    }

    /// The zone is gone: deleted on another device or in the iCloud settings (syncing turns off and says why), or
    /// its encrypted data was reset (everything is uploaded again).
    func zoneDeleted(encryptedDataReset: Bool) async {
        if encryptedDataReset {
            state.systemFields = [:]
            enqueue(SyncMerge.everything(in: model.library))
            return
        }
        await stop(forgetting: true, status: .failed(Self.deletedMessage))
        onTurnedOff?(Self.deletedMessage)
    }

    // MARK: State

    private func enqueue(_ changes: SyncChanges) {
        guard engine != nil, !changes.isEmpty else { return }
        state.add(changes)
        engine?.enqueue(changes)
        persist()
    }

    private func succeeded() {
        state.lastSync = now()
        status = .synced(state.lastSync)
        persist()
    }

    private func fail(_ error: any Error) {
        Log.sync.error("Syncing failed: \(error.localizedDescription, privacy: .public)")
        status = .failed(error.localizedDescription)
    }

    private func persist() {
        persisting = Task { [stateStore, state, previous = persisting] in
            await previous?.value
            await stateStore.save(state)
        }
    }

    /// Writes the state at once (at quit).
    func flush() async {
        await persisting?.value
        await stateStore.flush()
    }
}
