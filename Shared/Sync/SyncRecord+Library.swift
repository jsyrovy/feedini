import Foundation

// The records of the library's parts and back (pure). Only what is synced goes into a record: not a feed's download
// state (each device downloads on its own), a tombstone's later sightings, the AI usage or the page text list.
extension SyncRecord {
    typealias F = Field

    // MARK: Feed

    static let feedFields: Set<String> = [F.title, F.url, F.siteURL, F.language, F.folderID]

    init(feed: Feed) {
        self.init(.feed(feed.id))
        self[F.title] = .string(feed.title)
        self[F.url] = .string(feed.url.absoluteString)
        self[F.siteURL] = feed.siteURL.map { .string($0.absoluteString) }
        self[F.language] = feed.language.map(SyncValue.string)
        self[F.folderID] = feed.folderID.map { .string($0.uuidString) }
    }

    /// The feed with the download state of the local one (each device downloads on its own).
    func feed(keeping local: Feed?) -> Feed? {
        guard let id = id.uuid, let title = string(F.title), let url = url(F.url) else { return nil }
        var feed = local ?? Feed(id: id, title: title, url: url)
        feed.title = title
        feed.url = url
        feed.siteURL = self.url(F.siteURL)
        feed.language = string(F.language)
        feed.folderID = uuid(F.folderID)
        return feed
    }

    // MARK: Folder

    static let folderFields: Set<String> = [F.name, F.position]

    init(folder: Folder, position: Int) {
        self.init(.folder(folder.id))
        self[F.name] = .string(folder.name)
        self[F.position] = .int(position)
    }

    func folder() -> (folder: Folder, position: Int)? {
        guard let id = id.uuid, let name = string(F.name) else { return nil }
        return (Folder(id: id, name: name), int(F.position) ?? .max)
    }

    // MARK: Article

    /// What the feed said: the first write wins (both devices may download the same article).
    static let articleContentFields: Set<String> = [
        F.feedID, F.key, F.title, F.link, F.published, F.author, F.text, F.language, F.firstSeen, F.site,
    ]
    /// Reading and saving: the last write wins.
    static let articleStateFields: Set<String> = [F.readAt, F.savedAt]
    static let articleFields = articleContentFields.union(articleStateFields).union([F.pageSummary])

    init(article: Article) {
        self.init(.article(article.id))
        self[F.feedID] = .string(article.feedID.uuidString)
        self[F.key] = .string(article.key)
        self[F.title] = .string(article.title)
        self[F.link] = article.link.map { .string($0.absoluteString) }
        self[F.published] = article.published.map(SyncValue.date)
        self[F.author] = article.author.map(SyncValue.string)
        self[F.text] = .string(article.text)
        self[F.language] = article.language.map(SyncValue.string)
        self[F.firstSeen] = .date(article.firstSeen)
        self[F.site] = article.site.map(SyncValue.string)
        self[F.readAt] = article.readAt.map(SyncValue.date)
        self[F.savedAt] = article.savedAt.map(SyncValue.date)
        self[F.pageSummary] = article.pageSummary.flatMap { try? SyncRecord.encoder.encode($0) }.map(SyncValue.data)
    }

    func article() -> Article? {
        guard let id = id.uuid, let feedID = uuid(F.feedID), let key = string(F.key), let title = string(F.title),
            let firstSeen = date(F.firstSeen)
        else { return nil }
        return Article(
            id: id, feedID: feedID, key: key, title: title, link: url(F.link), published: date(F.published),
            author: string(F.author), text: string(F.text) ?? "", language: string(F.language), firstSeen: firstSeen,
            readAt: date(F.readAt), pageSummary: decoded(PageSummary.self, F.pageSummary), savedAt: date(F.savedAt),
            site: string(F.site))
    }

    // MARK: Page text

    init(pageText: String, of id: Article.ID) {
        self.init(.pageText(id))
        self[F.text] = .string(pageText)
    }

    var pageText: String? { string(F.text) }

    // MARK: Story, topic

    static let storyFields: Set<String> = [F.title, F.topicID, F.articleIDs, F.summary]

    init(story: Story) {
        self.init(.story(story.id))
        self[F.title] = .string(story.title)
        self[F.topicID] = story.topicID.map { .string($0.uuidString) }
        self[F.articleIDs] = .strings(story.articleIDs.map(\.uuidString))
        self[F.summary] = story.summary.flatMap { try? SyncRecord.encoder.encode($0) }.map(SyncValue.data)
    }

    func story() -> Story? {
        guard let id = id.uuid, let title = string(F.title) else { return nil }
        return Story(
            id: id, title: title, topicID: uuid(F.topicID),
            articleIDs: (strings(F.articleIDs) ?? []).compactMap(UUID.init(uuidString:)),
            summary: decoded(Summary.self, F.summary))
    }

    static let topicFields: Set<String> = [F.name, F.description, F.language]

    init(topic: Topic) {
        self.init(.topic(topic.id))
        self[F.name] = .string(topic.name)
        self[F.description] = .string(topic.description)
        self[F.language] = topic.language.map(SyncValue.string)
    }

    func topic() -> Topic? {
        guard let id = id.uuid, let name = string(F.name) else { return nil }
        return Topic(id: id, name: name, description: string(F.description) ?? "", language: string(F.language))
    }

    // MARK: Tombstone, removed feed

    /// `lastSeen` is only the first value: later sightings stay on each device.
    static let tombstoneFields: Set<String> = [F.feedID, F.key, F.lastSeen]

    init(tombstone: Tombstone) {
        self.init(.tombstone(tombstone.id))
        self[F.feedID] = .string(tombstone.feedID.uuidString)
        self[F.key] = .string(tombstone.key)
        self[F.lastSeen] = .date(tombstone.lastSeen)
    }

    func tombstone() -> Tombstone? {
        guard let feedID = uuid(F.feedID), let key = string(F.key), let lastSeen = date(F.lastSeen) else { return nil }
        return Tombstone(feedID: feedID, key: key, lastSeen: lastSeen)
    }

    init(removedFeed id: Feed.ID, title: String) {
        self.init(.removedFeed(id))
        self[F.title] = .string(title)
    }

    var removedFeedTitle: String? { string(F.title) }

    // MARK: Settings, meta

    static let settingsFields: Set<String> = [F.summaryLanguage, F.singleArticleSummaries]

    init(settings: SummarySettings) {
        self.init(.settings)
        self[F.summaryLanguage] = .string(settings.language)
        self[F.singleArticleSummaries] = .string(settings.singleArticles.rawValue)
    }

    func settings() -> SummarySettings? {
        guard let language = string(F.summaryLanguage) else { return nil }
        return SummarySettings(
            language: language,
            singleArticles: string(F.singleArticleSummaries).flatMap(SingleArticleSummaries.init(rawValue:))
                ?? .never)
    }

    init(minimumVersion: Int) {
        self.init(.meta)
        self[F.minimumVersion] = .int(minimumVersion)
    }

    var minimumVersion: Int? { int(F.minimumVersion) }

    // MARK: From the library

    /// The record of the library's part with the ID as it is now; `nil` when the library doesn't have it (anymore).
    /// A page text record needs its text, which is in a file: `pageText`. A tombstone is found through
    /// `tombstoneKeys` (made here when not given).
    static func make(
        _ id: ID, from library: Library, pageText: String? = nil, tombstoneKeys: [UUID: Tombstone.Key]? = nil
    ) -> SyncRecord? {
        guard let uuid = id.uuid else {
            switch id.kind {
            case .settings: return library.summarySettings.map(SyncRecord.init(settings:))
            case .meta: return SyncRecord(minimumVersion: SyncSchema.version)
            default: return nil
            }
        }
        switch id.kind {
        case .feed:
            return library.feed(uuid).map(SyncRecord.init(feed:))
        case .folder:
            guard let position = library.folders.firstIndex(where: { $0.id == uuid }) else { return nil }
            return SyncRecord(folder: library.folders[position], position: position)
        case .article:
            return library.articles[uuid].map(SyncRecord.init(article:))
        case .pageText:
            guard library.pageTextIDs.contains(uuid), let pageText else { return nil }
            return SyncRecord(pageText: pageText, of: uuid)
        case .story:
            return library.stories[uuid].map(SyncRecord.init(story:))
        case .topic:
            return library.topics[uuid].map(SyncRecord.init(topic:))
        case .tombstone:
            let key = (tombstoneKeys ?? Self.tombstoneKeys(in: library))[uuid]
            return key.flatMap { library.tombstones[$0] }.map(SyncRecord.init(tombstone:))
        case .removedFeed:
            return library.removedFeeds[uuid].map { SyncRecord(removedFeed: uuid, title: $0) }
        case .settings, .meta:
            return nil
        }
    }

    /// The library's tombstones by the UUID of their record. That UUID is a hash of the key, so finding a tombstone by
    /// it hashes every tombstone: made once for many lookups.
    static func tombstoneKeys(in library: Library) -> [UUID: Tombstone.Key] {
        Dictionary(
            library.tombstones.keys.compactMap { key in ID.tombstone(key).uuid.map { ($0, key) } },
            uniquingKeysWith: { first, _ in first })
    }
}
