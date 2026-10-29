import Foundation
import Testing

@testable import Feedini

@MainActor
struct PreferencesTests {
    private let defaults: UserDefaults

    init() {
        let suite = "feedini-tests-\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
    }

    @Test func defaultsToFifteenMinutesAndTheWindow() {
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.refreshMinutes == 15)
        #expect(preferences.pageOpening == .window)
    }

    @Test func savesChangesAndReportsThem() {
        let preferences = Preferences(defaults: defaults)
        var changes = 0
        preferences.onChange = { changes += 1 }

        preferences.refreshMinutes = 60
        preferences.pageOpening = .browser

        #expect(changes == 2)
        let reloaded = Preferences(defaults: defaults)
        #expect(reloaded.refreshMinutes == 60)
        #expect(reloaded.pageOpening == .browser)
    }

    @Test func ignoresValuesThatArentOffered() {
        defaults.set(7, forKey: "refreshMinutes")
        defaults.set("tab", forKey: "pageOpening")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.refreshMinutes == 15)
        #expect(preferences.pageOpening == .window)
    }
}
