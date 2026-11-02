import Foundation

/// A subscribed feed.
struct Feed: Codable, Sendable, Hashable, Identifiable {
    var id: UUID
    /// The title shown in the app: the feed's own title, or the host when it has none.
    var title: String
    /// The feed URL; always HTTPS.
    var url: URL
    /// The web site the feed belongs to.
    var siteURL: URL?
    /// The primary language code from the feed's `<language>` (`cs`, `en`, …), if it gives one.
    var language: String?
    /// Validators of the last download, for conditional GET.
    var etag: String?
    var lastModified: String?
    /// When the feed was last downloaded in full (not "not modified"): tombstones are judged against it.
    var lastSuccess: Date?
    /// When the feed was last checked successfully, including "not modified".
    var lastChecked: Date?
    /// Why the last refresh failed; `nil` after a successful one.
    var lastError: String?
    /// The folder the feed is in, if any.
    var folderID: Folder.ID?

    init(
        id: UUID = UUID(), title: String, url: URL, siteURL: URL? = nil, language: String? = nil,
        etag: String? = nil, lastModified: String? = nil, lastSuccess: Date? = nil, lastChecked: Date? = nil,
        lastError: String? = nil, folderID: Folder.ID? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteURL = siteURL
        self.language = language
        self.etag = etag
        self.lastModified = lastModified
        self.lastSuccess = lastSuccess
        self.lastChecked = lastChecked
        self.lastError = lastError
        self.folderID = folderID
    }
}
