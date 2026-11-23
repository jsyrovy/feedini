import Foundation

/// The version of the data in the iCloud zone (pure). Raised only by a change that adding a field can't solve: an
/// app that supports less stops syncing (keeping its data and the zone's) and asks to be updated. A newer app writes
/// the higher version (the `meta` record's `minimumVersion`) only once it really sends such data.
enum SyncSchema {
    static let version = 1

    /// Whether this app can sync a zone that needs `minimumVersion`; a zone without one (`nil`) is new.
    static func supports(minimumVersion: Int?) -> Bool {
        (minimumVersion ?? 0) <= version
    }

    static let updateMessage = "Update Feedini to keep syncing."
}
