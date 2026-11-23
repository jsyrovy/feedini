import Foundation

/// The synced records that changed between two libraries (pure): those to save with the fields that changed, and
/// those to delete. Only synced fields count, so a refresh that only records `lastChecked` changes nothing.
struct SyncChanges: Equatable, Sendable {
    /// The records to save, with the fields this device changed (every field of a new record).
    var saves: [SyncRecord.ID: Set<String>] = [:]
    var deletes: Set<SyncRecord.ID> = []

    var isEmpty: Bool { saves.isEmpty && deletes.isEmpty }

    /// Adds later changes: a save after a delete saves again, a delete drops the pending save.
    mutating func add(_ later: SyncChanges) {
        for (id, fields) in later.saves {
            deletes.remove(id)
            saves[id, default: []].formUnion(fields)
        }
        for id in later.deletes {
            saves[id] = nil
            deletes.insert(id)
        }
    }

    mutating func save(_ id: SyncRecord.ID, fields: Set<String>) {
        add(SyncChanges(saves: [id: fields]))
    }

    /// Unchanged collections share their storage, so comparing them costs nothing; only what changed is gone through.
    /// `articles` names the only articles that may have changed (reading and saving know them), so the others
    /// aren't compared one by one.
    static func diff(old: Library, new: Library, articles: Set<Article.ID>? = nil) -> SyncChanges {
        var changes = SyncChanges()
        if old.feeds != new.feeds {
            changes.compare(
                Dictionary(uniqueKeysWithValues: old.feeds.map { ($0.id, $0) }),
                Dictionary(uniqueKeysWithValues: new.feeds.map { ($0.id, $0) }), id: SyncRecord.ID.feed,
                record: SyncRecord.init(feed:), fields: SyncRecord.feedFields)
        }
        if old.folders != new.folders {
            changes.compare(
                folderRecords(old), folderRecords(new), id: SyncRecord.ID.folder, record: { $0 },
                fields: SyncRecord.folderFields)
        }
        if let articles {
            let pick = { (library: Library) in
                Dictionary(uniqueKeysWithValues: articles.compactMap { id in library.articles[id].map { (id, $0) } })
            }
            changes.compare(
                pick(old), pick(new), id: SyncRecord.ID.article, record: SyncRecord.init(article:),
                fields: SyncRecord.articleFields)
        } else if old.articles != new.articles {
            changes.compare(
                old.articles, new.articles, id: SyncRecord.ID.article, record: SyncRecord.init(article:),
                fields: SyncRecord.articleFields)
        }
        if old.stories != new.stories {
            changes.compare(
                old.stories, new.stories, id: SyncRecord.ID.story, record: SyncRecord.init(story:),
                fields: SyncRecord.storyFields)
        }
        if old.topics != new.topics {
            changes.compare(
                old.topics, new.topics, id: SyncRecord.ID.topic, record: SyncRecord.init(topic:),
                fields: SyncRecord.topicFields)
        }
        // Later sightings (`lastSeen`) aren't synced: only new and removed tombstones count.
        if old.tombstones != new.tombstones {
            for key in new.tombstones.keys where old.tombstones[key] == nil {
                changes.saves[.tombstone(key)] = SyncRecord.tombstoneFields
            }
            for key in old.tombstones.keys where new.tombstones[key] == nil {
                changes.deletes.insert(.tombstone(key))
            }
        }
        if old.removedFeeds != new.removedFeeds {
            for (id, title) in new.removedFeeds where old.removedFeeds[id] != title {
                changes.saves[.removedFeed(id)] = [SyncRecord.Field.title]
            }
            for id in old.removedFeeds.keys where new.removedFeeds[id] == nil {
                changes.deletes.insert(.removedFeed(id))
            }
        }
        if old.pageTextIDs != new.pageTextIDs {
            for id in new.pageTextIDs.subtracting(old.pageTextIDs) {
                changes.saves[.pageText(id)] = [SyncRecord.Field.text]
            }
            for id in old.pageTextIDs.subtracting(new.pageTextIDs) {
                changes.deletes.insert(.pageText(id))
            }
        }
        // The settings are never deleted.
        if let settings = new.summarySettings, settings != old.summarySettings {
            let before = old.summarySettings.map(SyncRecord.init(settings:))
            changes.saves[.settings] = changedFields(
                before, SyncRecord(settings: settings), among: SyncRecord.settingsFields)
        }
        return changes
    }

    private static func folderRecords(_ library: Library) -> [Folder.ID: SyncRecord] {
        Dictionary(
            uniqueKeysWithValues: library.folders.enumerated().map {
                ($1.id, SyncRecord(folder: $1, position: $0))
            })
    }

    /// Records of values that are new or differ (only values that aren't equal are turned into records), and of
    /// those that are gone.
    private mutating func compare<Key: Hashable, Value: Equatable>(
        _ old: [Key: Value], _ new: [Key: Value], id: (Key) -> SyncRecord.ID, record: (Value) -> SyncRecord,
        fields: Set<String>
    ) {
        for (key, value) in new {
            let before = old[key]
            guard before != value else { continue }
            let changed = Self.changedFields(before.map(record), record(value), among: fields)
            if !changed.isEmpty {
                saves[id(key)] = changed
            }
        }
        for key in old.keys where new[key] == nil {
            deletes.insert(id(key))
        }
    }

    /// Every field of a new record, else those whose values differ.
    private static func changedFields(_ old: SyncRecord?, _ new: SyncRecord, among fields: Set<String>) -> Set<String> {
        guard let old else { return fields }
        return fields.filter { old[$0] != new[$0] }
    }
}
