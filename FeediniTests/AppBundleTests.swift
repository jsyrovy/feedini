import Foundation
import Testing

@testable import Feedini

struct AppBundleTests {
    @Test func hostAppHasExpectedBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "cz.jsyrovy.feedini")
    }

    @Test func hostAppHasAVersion() {
        #expect(RuntimeEnvironment.appVersion.wholeMatch(of: #/[0-9]+\.[0-9]+/#) != nil)
    }

    /// `make` passes the commit (`FEEDINI_COMMIT`) into the Info.plist.
    @Test func hostAppKnowsItsCommit() throws {
        let commit = try #require(RuntimeEnvironment.commit)
        #expect(commit.wholeMatch(of: #/[0-9a-f]{7,}(-dirty)?/#) != nil)
    }

    @Test func versionDescriptionShowsTheCommitWhenKnown() {
        #expect(RuntimeEnvironment.versionDescription(version: "0.4", commit: "4ceb8b3") == "0.4 (4ceb8b3)")
        #expect(RuntimeEnvironment.versionDescription(version: "0.4", commit: nil) == "0.4")
    }

    @Test func hostAppKnowsItIsRunningTests() {
        #expect(RuntimeEnvironment.isRunningTests)
    }
}
