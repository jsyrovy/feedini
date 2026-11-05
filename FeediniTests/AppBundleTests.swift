import Foundation
import Testing

@testable import Feedini

struct AppBundleTests {
    @Test func hostAppHasExpectedBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "cz.jsyrovy.feedini")
    }

    @Test func hostAppHasAVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version?.wholeMatch(of: #/[0-9]+\.[0-9]+/#) != nil)
    }

    @Test func hostAppKnowsItIsRunningTests() {
        #expect(RuntimeEnvironment.isRunningTests)
    }
}
