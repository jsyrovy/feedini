import CloudKit
import Foundation

/// The `CKSyncEngine` behind the `SyncController`: one zone (`Library`) in the private database of the container.
/// A thin layer: it turns `CKRecord`s into `SyncRecord`s (and back) before they reach the main actor, and hands the
/// engine's events to the controller. Not unit-tested (it needs iCloud); everything it decides is in the controller.
@MainActor
final class CloudSyncEngine: SyncEngining {
    nonisolated static let containerIdentifier = "iCloud.cz.jsyrovy.feedini"
    nonisolated static let zoneID = CKRecordZone.ID(zoneName: "Library", ownerName: CKCurrentUserDefaultName)

    private var engine: CKSyncEngine?
    private let delegate: Delegate

    init(
        state: SyncState, controller: SyncController,
        container: CKContainer = CKContainer(identifier: containerIdentifier)
    ) {
        delegate = Delegate(controller: controller)
        let serialization = state.engine.flatMap {
            try? JSONDecoder().decode(CKSyncEngine.State.Serialization.self, from: $0)
        }
        let configuration = CKSyncEngine.Configuration(
            database: container.privateCloudDatabase, stateSerialization: serialization, delegate: delegate)
        let engine = CKSyncEngine(configuration)
        // Creates the zone the first time (a no-op later).
        if serialization == nil {
            engine.state.add(pendingDatabaseChanges: [.saveZone(CKRecordZone(zoneID: Self.zoneID))])
        }
        self.engine = engine
    }

    func enqueue(_ changes: SyncChanges) {
        let saves = changes.saves.keys.map { CKSyncEngine.PendingRecordZoneChange.saveRecord(Self.recordID($0)) }
        let deletes = changes.deletes.map { CKSyncEngine.PendingRecordZoneChange.deleteRecord(Self.recordID($0)) }
        engine?.state.add(pendingRecordZoneChanges: saves + deletes)
    }

    /// Fetches the changes the engine knows of: it learns of them by push, so without push this finds nothing.
    func fetchChanges() async throws {
        try await engine?.fetchChanges()
    }

    func sendChanges() async throws {
        try await engine?.sendChanges()
    }

    func deleteZone() async throws {
        guard let engine else { return }
        engine.state.add(pendingDatabaseChanges: [.deleteZone(Self.zoneID)])
        try await engine.sendChanges()
    }

    func cancel() {
        guard let engine else { return }
        self.engine = nil
        Task { await engine.cancelOperations() }
    }

    /// Why the iCloud account can't sync now; `nil` when it can. Needs the iCloud entitlement (`CKContainer` traps
    /// without it).
    nonisolated static func accountProblem() async -> String? {
        let status = try? await CKContainer(identifier: containerIdentifier).accountStatus()
        switch status {
        case .available: return nil
        case .noAccount: return SyncController.signedOutMessage
        case .restricted: return "iCloud is restricted on this device."
        case .temporarilyUnavailable: return "iCloud is temporarily unavailable."
        default: return "iCloud can't be reached."
        }
    }

    nonisolated static func recordID(_ id: SyncRecord.ID) -> CKRecord.ID {
        CKRecord.ID(recordName: id.name, zoneID: zoneID)
    }

    // MARK: Records

    /// The record to save: over the zone's record (its system fields) when known, with the given fields set.
    nonisolated static func ckRecord(
        _ record: SyncRecord, systemFields: Data?, fields: Set<String>, recordID: CKRecord.ID
    ) -> CKRecord {
        let ckRecord =
            systemFields.flatMap(decodeSystemFields)
            ?? CKRecord(recordType: record.id.kind.rawValue, recordID: recordID)
        let encrypted = record.id.kind.encryptedFields
        for field in fields {
            let value: (any __CKRecordObjCValue)? =
                switch record[field] {
                case .string(let string): string as NSString
                case .int(let int): NSNumber(value: int)
                case .date(let date): date as NSDate
                case .strings(let strings): strings as NSArray
                case .data(let data): data as NSData
                case nil: nil
                }
            if encrypted.contains(field) {
                ckRecord.encryptedValues[field] = value
            } else {
                ckRecord[field] = value
            }
        }
        return ckRecord
    }

    /// The record as fields with its system fields; `nil` for a record type this version doesn't know.
    nonisolated static func fetched(_ record: CKRecord) -> FetchedRecord? {
        guard let id = SyncRecord.ID(name: record.recordID.recordName) else { return nil }
        var fields: [String: SyncValue] = [:]
        let encrypted = Set(record.encryptedValues.allKeys())
        for key in record.allKeys() where !encrypted.contains(key) {
            fields[key] = value(record[key])
        }
        for key in encrypted {
            fields[key] = value(record.encryptedValues[key])
        }
        return FetchedRecord(record: SyncRecord(id, fields: fields), systemFields: encodeSystemFields(of: record))
    }

    private nonisolated static func value(_ object: Any?) -> SyncValue? {
        switch object {
        case let string as String: .string(string)
        case let date as Date: .date(date)
        case let number as NSNumber: .int(number.intValue)
        case let strings as [String]: .strings(strings)
        case let data as Data: .data(data)
        default: nil
        }
    }

    nonisolated static func encodeSystemFields(of record: CKRecord) -> Data {
        let coder = NSKeyedArchiver(requiringSecureCoding: true)
        record.encodeSystemFields(with: coder)
        coder.finishEncoding()
        return coder.encodedData
    }

    private nonisolated static func decodeSystemFields(_ data: Data) -> CKRecord? {
        guard let coder = try? NSKeyedUnarchiver(forReadingFrom: data) else { return nil }
        coder.requiresSecureCoding = true
        defer { coder.finishDecoding() }
        return CKRecord(coder: coder)
    }

    // MARK: Events

    /// The engine's delegate: it holds the controller (a main-actor object) and nothing else.
    private final class Delegate: CKSyncEngineDelegate {
        let controller: SyncController

        init(controller: SyncController) {
            self.controller = controller
        }

        func handleEvent(_ event: CKSyncEngine.Event, syncEngine: CKSyncEngine) async {
            switch event {
            case .stateUpdate(let update):
                if let data = try? JSONEncoder().encode(update.stateSerialization) {
                    await controller.stateChanged(data)
                }
            case .accountChange(let change):
                switch change.changeType {
                case .signIn: await controller.accountChanged(.signIn)
                case .signOut: await controller.accountChanged(.signOut)
                case .switchAccounts: await controller.accountChanged(.switchAccounts)
                @unknown default: break
                }
            case .fetchedDatabaseChanges(let changes):
                for deletion in changes.deletions where deletion.zoneID == CloudSyncEngine.zoneID {
                    await controller.zoneDeleted(encryptedDataReset: deletion.reason == .encryptedDataReset)
                }
            case .fetchedRecordZoneChanges(let changes):
                let records = changes.modifications.compactMap { CloudSyncEngine.fetched($0.record) }
                let deletions = changes.deletions.compactMap { SyncRecord.ID(name: $0.recordID.recordName) }
                await controller.fetched(records, deletions: deletions)
            case .sentRecordZoneChanges(let sent):
                await handleSent(sent, syncEngine: syncEngine)
            case .willFetchChanges:
                await controller.willFetch()
            case .didFetchChanges:
                await controller.didFetch()
            case .sentDatabaseChanges, .willFetchRecordZoneChanges, .didFetchRecordZoneChanges, .willSendChanges,
                .didSendChanges:
                break
            @unknown default:
                break
            }
        }

        private func handleSent(_ sent: CKSyncEngine.Event.SentRecordZoneChanges, syncEngine: CKSyncEngine) async {
            let saved = sent.savedRecords.compactMap { record in
                SyncRecord.ID(name: record.recordID.recordName).map {
                    (id: $0, systemFields: CloudSyncEngine.encodeSystemFields(of: record))
                }
            }
            let deleted = sent.deletedRecordIDs.compactMap { SyncRecord.ID(name: $0.recordName) }
            var conflicts: [FetchedRecord] = []
            var missing: [SyncRecord.ID] = []
            var failures: [(id: SyncRecord.ID, message: String)] = []
            for failure in sent.failedRecordSaves {
                guard let id = SyncRecord.ID(name: failure.record.recordID.recordName) else { continue }
                switch failure.error.code {
                case .serverRecordChanged:
                    if let server = failure.error.serverRecord.flatMap(CloudSyncEngine.fetched) {
                        conflicts.append(server)
                    }
                case .unknownItem:
                    missing.append(id)
                case .zoneNotFound:
                    syncEngine.state.add(pendingDatabaseChanges: [
                        .saveZone(CKRecordZone(zoneID: CloudSyncEngine.zoneID))
                    ])
                    syncEngine.state.add(pendingRecordZoneChanges: [.saveRecord(failure.record.recordID)])
                case .networkFailure, .networkUnavailable, .zoneBusy, .serviceUnavailable, .notAuthenticated,
                    .operationCancelled, .requestRateLimited:
                    // The engine tries again by itself.
                    break
                default:
                    failures.append((id, failure.error.localizedDescription))
                }
            }
            for (recordID, error) in sent.failedRecordDeletes {
                Log.sync.error(
                    "Deleting \(recordID.recordName, privacy: .public) failed: \(error.localizedDescription, privacy: .public)"
                )
            }
            await controller.sent(
                saved: saved, deleted: deleted, conflicts: conflicts, missing: missing, failures: failures)
        }

        func nextRecordZoneChangeBatch(
            _ context: CKSyncEngine.SendChangesContext, syncEngine: CKSyncEngine
        ) async -> CKSyncEngine.RecordZoneChangeBatch? {
            let scope = context.options.scope
            let changes = syncEngine.state.pendingRecordZoneChanges.filter { scope.contains($0) }
            let controller = controller
            return await CKSyncEngine.RecordZoneChangeBatch(pendingChanges: changes) { recordID in
                guard let id = SyncRecord.ID(name: recordID.recordName),
                    let toSend = await controller.recordToSend(id)
                else {
                    // Gone here meanwhile (or a type this version doesn't know): nothing to send.
                    syncEngine.state.remove(pendingRecordZoneChanges: [.saveRecord(recordID)])
                    return nil
                }
                return CloudSyncEngine.ckRecord(
                    toSend.record, systemFields: toSend.systemFields, fields: toSend.fields, recordID: recordID)
            }
        }
    }
}
