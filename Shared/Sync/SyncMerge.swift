import Foundation

/// The rules for records that come from the iCloud zone and for conflicts (pure). One user with one Mac and one
/// iPhone rarely changes the same thing on both at once, so the rules stay simple:
///
/// - What a feed said (an article's content) is written once: the first write wins.
/// - Reading and saving, feeds and folders: the last write wins.
/// - Stories, topics and the summary settings are written by the Mac only.
/// - "Unread forever" holds across devices: an article deleted on one device (retention, a removed feed) stays when
///   it is unread or saved on the other, and is created again; so does a story with an unread article.
/// - Merging two libraries (the first sync of a device that has data while the zone has some too): feeds and articles
///   by their stable IDs, read or saved on either side means read or saved (the earlier date), folders of the same
///   name become the zone's.
///
/// Page texts aren't applied here: their text goes into a file (`SyncEngine`).
enum SyncMerge {
    enum Mode: Sendable {
        /// A change of the other device.
        case update
        /// Merging this device's library with the zone's.
        case merge
    }

    /// Applies a record fetched from the zone. Fields this device changed and hasn't sent yet (`pending`) keep their
    /// local values: they go out and are resolved then. Returns the changes this device has to send because of it
    /// (merging).
    @discardableResult
    static func apply(
        _ record: SyncRecord, to library: inout Library, pending: Set<String> = [], mode: Mode = .update
    ) -> SyncChanges {
        guard let uuid = record.id.uuid else {
            if record.id.kind == .settings, let settings = record.settings() {
                library.summarySettings = settings
            }
            return SyncChanges()
        }
        switch record.id.kind {
        case .feed:
            let local = library.feed(uuid)
            let effective = local.map { record.taking(pending, from: SyncRecord(feed: $0)) } ?? record
            guard let feed = effective.feed(keeping: local) else { return SyncChanges() }
            if let index = library.feeds.firstIndex(where: { $0.id == uuid }) {
                library.feeds[index] = feed
            } else {
                library.feeds.append(feed)
            }
        case .folder:
            return applyFolder(record, uuid: uuid, to: &library, pending: pending)
        case .article:
            return applyArticle(record, uuid: uuid, to: &library, pending: pending, mode: mode)
        case .story:
            let effective = library.stories[uuid].map { record.taking(pending, from: SyncRecord(story: $0)) } ?? record
            library.stories[uuid] = effective.story() ?? library.stories[uuid]
        case .topic:
            let effective = library.topics[uuid].map { record.taking(pending, from: SyncRecord(topic: $0)) } ?? record
            library.topics[uuid] = effective.topic() ?? library.topics[uuid]
        case .tombstone:
            // Later sightings stay this device's.
            if let tombstone = record.tombstone(), library.tombstones[tombstone.id] == nil {
                library.tombstones[tombstone.id] = tombstone
            }
        case .removedFeed:
            if let title = record.removedFeedTitle {
                library.removedFeeds[uuid] = title
            }
        case .pageText, .settings, .meta:
            break
        }
        return SyncChanges()
    }

    /// Applies a deletion by the other device; returns what this device has to send back: a record it keeps and
    /// creates again (`recreates`).
    @discardableResult
    static func delete(_ id: SyncRecord.ID, from library: inout Library) -> SyncChanges {
        if recreates(id, in: library) {
            return SyncChanges(saves: [id: allFields(of: id.kind)])
        }
        guard let uuid = id.uuid else { return SyncChanges() }
        switch id.kind {
        case .feed: library.removeFeed(uuid)
        case .folder: library.removeFolder(uuid)
        case .article: library.removeArticles([uuid])
        case .pageText: library.pageTextIDs.remove(uuid)
        case .story: library.stories[uuid] = nil
        case .topic: library.topics[uuid] = nil
        case .tombstone: library.tombstones = library.tombstones.filter { SyncRecord.ID.tombstone($0.key) != id }
        case .removedFeed: library.removedFeeds[uuid] = nil
        case .settings, .meta: break
        }
        return SyncChanges()
    }

    /// Whether a record the other device deleted stays and is created again: an unread or saved article, a story or
    /// topic still in use, the settings. Everything else goes.
    static func recreates(_ id: SyncRecord.ID, in library: Library) -> Bool {
        switch id.kind {
        case .article:
            guard let article = id.uuid.flatMap({ library.articles[$0] }) else { return false }
            return !article.isRead || article.isSaved
        case .story:
            guard let story = id.uuid.flatMap({ library.stories[$0] }) else { return false }
            return !library.unreadArticles(of: story).isEmpty
        case .topic:
            guard let uuid = id.uuid, library.topics[uuid] != nil else { return false }
            return library.stories.values.contains { $0.topicID == uuid && !library.unreadArticles(of: $0).isEmpty }
        case .settings:
            return library.summarySettings != nil
        case .feed, .folder, .pageText, .tombstone, .removedFeed, .meta:
            return false
        }
    }

    /// A conflict when saving (the zone has a newer record): the zone's record with the fields this device changed,
    /// except an article's content (the first write wins) and a tombstone (its first sighting stays). The result is
    /// saved again and applied here too.
    static func resolve(server: SyncRecord, local: SyncRecord, changed: Set<String>) -> SyncRecord {
        let kept: Set<String> =
            switch server.id.kind {
            case .article: SyncRecord.articleContentFields
            case .tombstone: SyncRecord.tombstoneFields
            default: []
            }
        return server.taking(changed.subtracting(kept), from: local)
    }

    /// The fields of a record type, for a record sent as a whole.
    static func allFields(of kind: SyncRecord.Kind) -> Set<String> {
        switch kind {
        case .feed: SyncRecord.feedFields
        case .folder: SyncRecord.folderFields
        case .article: SyncRecord.articleFields
        case .pageText: [SyncRecord.Field.text]
        case .story: SyncRecord.storyFields
        case .topic: SyncRecord.topicFields
        case .tombstone: SyncRecord.tombstoneFields
        case .removedFeed: [SyncRecord.Field.title]
        case .settings: SyncRecord.settingsFields
        case .meta: [SyncRecord.Field.minimumVersion]
        }
    }

    /// Every record of the library, for a first upload (after merging, or after the zone was reset).
    static func everything(in library: Library) -> SyncChanges {
        var changes = SyncChanges.diff(old: Library(), new: library)
        changes.saves[.meta] = allFields(of: .meta)
        return changes
    }

    // MARK: Parts

    /// A folder goes to its position; a folder of the same name (another device made it too) becomes this one, with
    /// its feeds, and is deleted.
    private static func applyFolder(
        _ record: SyncRecord, uuid: UUID, to library: inout Library, pending: Set<String>
    ) -> SyncChanges {
        let localIndex = library.folders.firstIndex { $0.id == uuid }
        let effective =
            localIndex.map { record.taking(pending, from: SyncRecord(folder: library.folders[$0], position: $0)) }
            ?? record
        guard let (folder, position) = effective.folder() else { return SyncChanges() }
        library.folders.removeAll { $0.id == uuid }
        library.folders.insert(folder, at: min(max(position, 0), library.folders.count))
        var changes = SyncChanges()
        let name = folder.name.lowercased()
        for twin in library.folders where twin.id != uuid && twin.name.lowercased() == name {
            let moved = library.feeds.filter { $0.folderID == twin.id }.map(\.id)
            library.moveFeeds(moved, to: uuid)
            for id in moved {
                changes.save(.feed(id), fields: [SyncRecord.Field.folderID])
            }
            library.removeFolder(twin.id)
            changes.add(SyncChanges(deletes: [.folder(twin.id)]))
        }
        return changes
    }

    /// An article's content comes from the zone; reading and saving too, unless pending here. Merging keeps what was
    /// read or saved on either side, at the earlier date, and sends that back when it differs from the zone's.
    private static func applyArticle(
        _ record: SyncRecord, uuid: UUID, to library: inout Library, pending: Set<String>, mode: Mode
    ) -> SyncChanges {
        let local = library.articles[uuid]
        let effective = local.map { record.taking(pending, from: SyncRecord(article: $0)) } ?? record
        guard var article = effective.article() else { return SyncChanges() }
        var changes = SyncChanges()
        if mode == .merge, let local {
            article.readAt = earlier(article.readAt, local.readAt)
            article.savedAt = earlier(article.savedAt, local.savedAt)
            article.pageSummary = newer(article.pageSummary, local.pageSummary)
            let sent = SyncRecord(article: article)
            let differing = SyncRecord.articleStateFields.union([SyncRecord.Field.pageSummary])
                .filter { sent[$0] != record[$0] }
            if !differing.isEmpty {
                changes.save(.article(uuid), fields: differing)
            }
        }
        library.articles[uuid] = article
        return changes
    }

    private static func earlier(_ lhs: Date?, _ rhs: Date?) -> Date? {
        guard let lhs, let rhs else { return lhs ?? rhs }
        return min(lhs, rhs)
    }

    private static func newer(_ lhs: PageSummary?, _ rhs: PageSummary?) -> PageSummary? {
        guard let lhs, let rhs else { return lhs ?? rhs }
        return rhs.date > lhs.date ? rhs : lhs
    }
}
