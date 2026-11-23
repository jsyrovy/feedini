import CloudKit
import Foundation
import Testing

@testable import Feedini

/// The conversion of records only: the engine itself needs iCloud.
struct CloudSyncEngineTests {
    private let article = Article(
        feedID: UUID(), key: "a", title: "A", link: URL(string: "https://example.com/a"), published: .hours(-3),
        text: "Text", firstSeen: .hours(-2), readAt: .hours(-1),
        pageSummary: PageSummary(tldr: "Gist", details: [], language: "en", date: .hours(-1)))

    @Test func aRecordGoesToCloudKitAndBackWithEncryptedContent() throws {
        let record = SyncRecord(article: article)
        let id = record.id
        let ckRecord = CloudSyncEngine.ckRecord(
            record, systemFields: nil, fields: SyncRecord.articleFields, recordID: CloudSyncEngine.recordID(id))

        #expect(ckRecord.recordType == "Article")
        #expect(ckRecord.recordID.recordName == id.name)
        #expect(ckRecord.recordID.zoneID.zoneName == "Library")
        #expect(ckRecord.encryptedValues["text"] as? String == "Text")
        #expect(ckRecord["readAt"] as? Date == .hours(-1))
        #expect(ckRecord["text"] == nil)

        let fetched = try #require(CloudSyncEngine.fetched(ckRecord))
        #expect(fetched.record.article() == article)
        #expect(!fetched.systemFields.isEmpty)
    }

    @Test func onlyTheGivenFieldsAreSetOverTheZonesRecord() throws {
        let id = SyncRecord.ID.article(article.id)
        let zone = CKRecord(recordType: "Article", recordID: CloudSyncEngine.recordID(id))
        let systemFields = CloudSyncEngine.encodeSystemFields(of: zone)
        var unread = article
        unread.readAt = nil

        let ckRecord = CloudSyncEngine.ckRecord(
            SyncRecord(article: unread), systemFields: systemFields, fields: [SyncRecord.Field.readAt],
            recordID: zone.recordID)

        #expect(ckRecord.changedKeys() == [SyncRecord.Field.readAt])
        #expect(ckRecord["readAt"] == nil)
        #expect(ckRecord.encryptedValues["title"] == nil)
    }

    @Test func recordsOfOtherTypesAndUnknownValuesAreLeftOut() throws {
        let other = CKRecord(
            recordType: "Highlight", recordID: CKRecord.ID(recordName: "highlight-\(UUID().uuidString)"))
        #expect(CloudSyncEngine.fetched(other) == nil)

        let folder = CKRecord(
            recordType: "Folder", recordID: CloudSyncEngine.recordID(.folder(UUID())))
        folder.encryptedValues["name"] = "Daily"
        folder["position"] = 2
        folder["color"] = ["a", "b"]
        folder["list"] = [1, 2] as [NSNumber]
        let fetched = try #require(CloudSyncEngine.fetched(folder))
        #expect(fetched.record.folder()?.folder.name == "Daily")
        #expect(fetched.record.folder()?.position == 2)
        #expect(fetched.record["color"] == .strings(["a", "b"]))
        #expect(fetched.record["list"] == nil)
    }
}
