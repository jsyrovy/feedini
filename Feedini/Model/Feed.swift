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
    /// When the feed was last downloaded successfully (including "not modified").
    var lastSuccess: Date?
    /// Why the last refresh failed; `nil` after a successful one.
    var lastError: String?

    init(
        id: UUID = UUID(), title: String, url: URL, siteURL: URL? = nil, language: String? = nil,
        etag: String? = nil, lastModified: String? = nil, lastSuccess: Date? = nil, lastError: String? = nil
    ) {
        self.id = id
        self.title = title
        self.url = url
        self.siteURL = siteURL
        self.language = language
        self.etag = etag
        self.lastModified = lastModified
        self.lastSuccess = lastSuccess
        self.lastError = lastError
    }
}
