import Foundation

/// A value of a synced record's field: what a `CKRecord` field holds, without CloudKit (pure).
enum SyncValue: Equatable, Sendable {
    case string(String)
    case int(Int)
    case date(Date)
    case strings([String])
    case data(Data)
}

/// One record of the library in the iCloud zone, as fields (pure; `SyncEngine` turns it into a `CKRecord`). A missing
/// field is `nil`. Fields this version doesn't know are kept as they are: an older Feedini must not drop what a
/// newer one wrote.
struct SyncRecord: Equatable, Sendable {
    /// The record types; the raw value is the `CKRecord` type.
    enum Kind: String, CaseIterable, Sendable {
        case feed = "Feed"
        case folder = "Folder"
        case article = "Article"
        case pageText = "PageText"
        case story = "Story"
        case topic = "Topic"
        case tombstone = "Tombstone"
        case removedFeed = "RemovedFeed"
        case settings = "Settings"
        case meta = "Meta"

        /// The prefix of the record name: names must be unique in the zone across types.
        var prefix: String {
            switch self {
            case .feed: "feed"
            case .folder: "folder"
            case .article: "article"
            case .pageText: "pagetext"
            case .story: "story"
            case .topic: "topic"
            case .tombstone: "tombstone"
            case .removedFeed: "removedfeed"
            case .settings: "settings"
            case .meta: "meta"
            }
        }

        /// Settings and meta are single records without an ID.
        var isSingle: Bool { self == .settings || self == .meta }

        /// The fields that go into `encryptedValues` (end-to-end encrypted with Advanced Data Protection): what the
        /// user reads or what tells what they read. IDs, dates and the order stay plain.
        var encryptedFields: Set<String> {
            switch self {
            case .feed: [Field.title, Field.url, Field.siteURL, Field.language]
            case .folder: [Field.name]
            case .article:
                [
                    Field.key, Field.title, Field.link, Field.author, Field.text, Field.language, Field.site,
                    Field.pageSummary,
                ]
            case .pageText: [Field.text]
            case .story: [Field.title, Field.summary]
            case .topic: [Field.name, Field.description, Field.language]
            case .tombstone: [Field.key]
            case .removedFeed: [Field.title]
            case .settings: [Field.summaryLanguage]
            case .meta: []
            }
        }
    }

    /// The name of a record: `<prefix>-<uuid>`, or the prefix alone for a single record.
    struct ID: Hashable, Sendable {
        var kind: Kind
        /// `nil` for a single record.
        var uuid: UUID?

        init(_ kind: Kind, _ uuid: UUID? = nil) {
            self.kind = kind
            self.uuid = kind.isSingle ? nil : uuid
        }

        /// `nil` for a name of a type this version doesn't know (it is left alone).
        init?(name: String) {
            if let kind = Kind.allCases.first(where: { $0.isSingle && $0.prefix == name }) {
                self.init(kind)
                return
            }
            guard let dash = name.firstIndex(of: "-"),
                let kind = Kind.allCases.first(where: { !$0.isSingle && $0.prefix == name[..<dash] }),
                let uuid = UUID(uuidString: String(name[name.index(after: dash)...]))
            else { return nil }
            self.init(kind, uuid)
        }

        var name: String {
            guard let uuid else { return kind.prefix }
            return "\(kind.prefix)-\(uuid.uuidString)"
        }
    }

    /// The names of the fields (in `CKRecord` they are the keys).
    enum Field {
        static let title = "title"
        static let url = "url"
        static let siteURL = "siteURL"
        static let language = "language"
        static let folderID = "folderID"
        static let name = "name"
        static let position = "position"
        static let feedID = "feedID"
        static let key = "key"
        static let link = "link"
        static let published = "published"
        static let author = "author"
        static let text = "text"
        static let firstSeen = "firstSeen"
        static let site = "site"
        static let readAt = "readAt"
        static let savedAt = "savedAt"
        static let pageSummary = "pageSummary"
        static let topicID = "topicID"
        static let articleIDs = "articleIDs"
        static let summary = "summary"
        static let description = "description"
        static let lastSeen = "lastSeen"
        static let summaryLanguage = "summaryLanguage"
        static let singleArticleSummaries = "singleArticleSummaries"
        static let minimumVersion = "minimumVersion"
    }

    var id: ID
    var fields: [String: SyncValue]

    init(_ id: ID, fields: [String: SyncValue] = [:]) {
        self.id = id
        self.fields = fields
    }

    subscript(_ field: String) -> SyncValue? {
        get { fields[field] }
        set { fields[field] = newValue }
    }

    /// The record with the given fields taken from `other` (removed where `other` has none); the rest, unknown
    /// fields too, stay as they are.
    func taking(_ names: Set<String>, from other: SyncRecord) -> SyncRecord {
        var record = self
        for name in names {
            record.fields[name] = other.fields[name]
        }
        return record
    }

    // MARK: Reading fields

    func string(_ field: String) -> String? {
        if case .string(let value) = fields[field] { value } else { nil }
    }

    func int(_ field: String) -> Int? {
        if case .int(let value) = fields[field] { value } else { nil }
    }

    func date(_ field: String) -> Date? {
        if case .date(let value) = fields[field] { value } else { nil }
    }

    func strings(_ field: String) -> [String]? {
        if case .strings(let value) = fields[field] { value } else { nil }
    }

    func data(_ field: String) -> Data? {
        if case .data(let value) = fields[field] { value } else { nil }
    }

    func url(_ field: String) -> URL? {
        string(field).flatMap(URL.init(string:))
    }

    func uuid(_ field: String) -> UUID? {
        string(field).flatMap(UUID.init(uuidString:))
    }

    /// A Codable value stored as JSON (summaries).
    func decoded<Value: Decodable>(_ type: Value.Type, _ field: String) -> Value? {
        data(field).flatMap { try? SyncRecord.decoder.decode(type, from: $0) }
    }

    static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension SyncRecord.ID {
    static func feed(_ id: Feed.ID) -> Self { Self(.feed, id) }
    static func folder(_ id: Folder.ID) -> Self { Self(.folder, id) }
    static func article(_ id: Article.ID) -> Self { Self(.article, id) }
    static func pageText(_ id: Article.ID) -> Self { Self(.pageText, id) }
    static func story(_ id: Story.ID) -> Self { Self(.story, id) }
    static func topic(_ id: Topic.ID) -> Self { Self(.topic, id) }
    /// A tombstone has the ID of the article it stands for (`StableID.article`).
    static func tombstone(_ key: Tombstone.Key) -> Self {
        Self(.tombstone, StableID.article(feed: key.feedID, key: key.key))
    }
    static func removedFeed(_ id: Feed.ID) -> Self { Self(.removedFeed, id) }
    static let settings = Self(.settings)
    static let meta = Self(.meta)
}
