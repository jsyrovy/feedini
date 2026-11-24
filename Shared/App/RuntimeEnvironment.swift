import Foundation

enum RuntimeEnvironment {
    /// True when the app is launched as the host of the unit test bundle.
    static let isRunningTests: Bool = {
        let environment = ProcessInfo.processInfo.environment
        return environment["XCTestConfigurationFilePath"] != nil || environment["XCTestBundlePath"] != nil
            || environment["XCTestSessionIdentifier"] != nil
    }()

    /// The app's version (`MARKETING_VERSION`).
    static let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? ""

    /// The commit the app was built from (`FeediniCommit`: the short hash, "-dirty" with uncommitted changes), set by
    /// `make` and `make release`; nil in a build without it (from Xcode).
    static let commit = (Bundle.main.infoDictionary?["FeediniCommit"] as? String).flatMap { $0.isEmpty ? nil : $0 }

    /// The version with the commit: "0.4 (4ceb8b3)", or the version alone.
    static let versionDescription = versionDescription(version: appVersion, commit: commit)

    static func versionDescription(version: String, commit: String?) -> String {
        guard let commit else { return version }
        return "\(version) (\(commit))"
    }
}
