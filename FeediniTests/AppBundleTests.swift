import Foundation
import Testing

@testable import Feedini

struct AppBundleTests {
    @Test func hostAppHasExpectedBundleIdentifier() {
        #expect(Bundle.main.bundleIdentifier == "cz.jsyrovy.feedini")
    }

    @Test func hostAppHasAVersion() {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        #expect(version == "0.1.0")
    }

    @Test func hostAppKnowsItIsRunningTests() {
        #expect(RuntimeEnvironment.isRunningTests)
    }
}
