import Security

/// Whether this build can use CloudKit: `CKContainer` traps without the iCloud entitlement, which ad-hoc builds (CI,
/// a build without the team) don't have.
enum SyncAvailability {
    static let notInThisBuild = "Sync isn't available in this build."

    /// The app's own `com.apple.developer.icloud-services` entitlement lists CloudKit.
    static var hasCloudKitEntitlement: Bool {
        guard let task = SecTaskCreateFromSelf(nil),
            let value = SecTaskCopyValueForEntitlement(task, "com.apple.developer.icloud-services" as CFString, nil)
        else { return false }
        return (value as? [String])?.contains("CloudKit") == true
    }

    /// Why syncing can't start now; `nil` when it can.
    static func problem() async -> String? {
        guard hasCloudKitEntitlement else { return notInThisBuild }
        return await CloudSyncEngine.accountProblem()
    }
}
