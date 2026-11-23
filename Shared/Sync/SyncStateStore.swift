import Foundation

/// What a device remembers about syncing, next to the library but not in it (nor in backups): the engine's state,
/// the system fields of the records it knows (so a save updates the zone's record instead of conflicting), the fields
/// changed here and not sent yet (for resolving conflicts), and whether the library still has to be merged with the
/// zone's.
struct SyncState: Codable, Equatable, Sendable {
    /// `CKSyncEngine.State.Serialization`, encoded.
    var engine: Data?
    /// `CKRecord.encodeSystemFields` by record name.
    var systemFields: [String: Data] = [:]
    /// The fields changed here and not sent yet, by record name.
    var changedFields: [String: Set<String>] = [:]
    /// Set until the first fetch after turning sync on has been merged into the library.
    var needsMerge = true
    /// The end of the last fetch or send that worked.
    var lastSync: Date?

    /// Records the changes to send.
    mutating func add(_ changes: SyncChanges) {
        for (id, fields) in changes.saves {
            changedFields[id.name, default: []].formUnion(fields)
        }
        for id in changes.deletes {
            changedFields[id.name] = nil
        }
    }

    func changedFields(of id: SyncRecord.ID) -> Set<String> {
        changedFields[id.name] ?? []
    }
}

/// Saves the `SyncState` as `sync.json` next to the library, debounced like the library (the engine reports state
/// changes often), atomically; `flush()` writes at once.
actor SyncStateStore {
    let fileURL: URL
    private let debounce: Duration
    private let sleep: @Sendable (Duration) async throws -> Void
    private var pending: SyncState?
    private var saveTask: Task<Void, Never>?

    init(
        fileURL: URL = SyncStateStore.defaultFileURL, debounce: Duration = .seconds(2),
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) }
    ) {
        self.fileURL = fileURL
        self.debounce = debounce
        self.sleep = sleep
    }

    /// `sync.json` next to `library.json`.
    static var defaultFileURL: URL {
        LibraryStore.defaultFileURL.deletingLastPathComponent().appending(path: "sync.json")
    }

    /// The saved state; a new one when there is none or it can't be read (syncing then starts over with a merge).
    func load() -> SyncState {
        guard let data = try? Data(contentsOf: fileURL) else { return SyncState() }
        do {
            return try JSONDecoder().decode(SyncState.self, from: data)
        } catch {
            Log.sync.error("The sync state couldn't be read: \(error.localizedDescription, privacy: .public)")
            return SyncState()
        }
    }

    func save(_ state: SyncState) {
        pending = state
        guard saveTask == nil else { return }
        saveTask = Task { [debounce, sleep] in
            try? await sleep(debounce)
            self.writePending()
        }
    }

    func flush() {
        saveTask?.cancel()
        writePending()
    }

    /// Forgets the state (sync turned off, another iCloud account): the next start merges again.
    func delete() {
        saveTask?.cancel()
        saveTask = nil
        pending = nil
        do {
            try FileManager.default.removeItem(at: fileURL)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            Log.sync.error("Deleting the sync state failed: \(error.localizedDescription, privacy: .public)")
        }
    }

    private func writePending() {
        saveTask = nil
        guard let state = pending else { return }
        pending = nil
        do {
            try FileManager.default.createDirectory(
                at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(state).write(to: fileURL, options: .atomic)
        } catch {
            Log.sync.error("Saving the sync state failed: \(error.localizedDescription, privacy: .public)")
        }
    }
}
