import Foundation

/// A read article that was removed from the library. Remembered while the article is still in its feed (plus a
/// margin), so a refresh doesn't bring it back as new.
struct Tombstone: Codable, Sendable, Hashable {
    var feedID: Feed.ID
    var key: String
    /// The last time the article was in its feed (or when it was removed, if later).
    var lastSeen: Date
}
