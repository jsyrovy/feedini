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
        #expect(preferences.showsUnreadCount)
    }

    @Test func savesWhetherTheMenuBarShowsTheCount() {
        Preferences(defaults: defaults).showsUnreadCount = false
        #expect(!Preferences(defaults: defaults).showsUnreadCount)
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

    @Test func aiDefaultsToHaikuWithLowEffort() {
        let preferences = Preferences(defaults: defaults)
        let configuration = preferences.aiConfiguration
        #expect(configuration.isEnabled)
        #expect(configuration.assignModel == "claude-haiku-5-5")
        #expect(configuration.summaryModel == "claude-haiku-5-5")
        #expect(configuration.effort == "low")
        #expect(configuration.claudePath == "")
        #expect(configuration.languageCode == OutputLanguage.systemCode)
        #expect(configuration.language == OutputLanguage.name(of: OutputLanguage.systemCode))
    }

    @Test func theSummaryLanguageDefaultsToTheSystem() {
        let preferences = Preferences(defaults: defaults)
        var aiChanges = 0
        preferences.onAIChange = { aiChanges += 1 }
        #expect(preferences.summaryLanguage == "")
        #expect(preferences.summaryLanguageCode == OutputLanguage.systemCode)

        preferences.summaryLanguage = "cs"

        #expect(aiChanges == 1)
        #expect(preferences.aiConfiguration.languageCode == "cs")
        #expect(preferences.aiConfiguration.language == "Czech")
        #expect(Preferences(defaults: defaults).summaryLanguage == "cs")
        defaults.set("not a language", forKey: "summaryLanguage")
        #expect(Preferences(defaults: defaults).summaryLanguage == "")
    }

    @Test func singleArticlesAreNotSummarizedByDefault() {
        let preferences = Preferences(defaults: defaults)
        var aiChanges = 0
        preferences.onAIChange = { aiChanges += 1 }
        #expect(preferences.singleArticleSummaries == .never)
        #expect(preferences.aiConfiguration.singleArticleSummaries == .never)

        preferences.singleArticleSummaries = .otherLanguages

        #expect(aiChanges == 1)
        #expect(preferences.aiConfiguration.singleArticleSummaries == .otherLanguages)
        #expect(Preferences(defaults: defaults).singleArticleSummaries == .otherLanguages)
        defaults.set("sometimes", forKey: "singleArticleSummaries")
        #expect(Preferences(defaults: defaults).singleArticleSummaries == .never)
    }

    @Test func savesAIChangesAndReportsThemSeparately() {
        let preferences = Preferences(defaults: defaults)
        var changes = 0
        var aiChanges = 0
        preferences.onChange = { changes += 1 }
        preferences.onAIChange = { aiChanges += 1 }

        preferences.aiEnabled = false
        preferences.claudePath = "/tools/claude"
        preferences.assignModel = "claude-sonnet-5-5"
        preferences.summaryModel = "claude-opus-5-5"
        preferences.aiEffort = "medium"

        #expect(aiChanges == 5)
        #expect(changes == 0)
        let reloaded = Preferences(defaults: defaults).aiConfiguration
        #expect(
            reloaded
                == AIConfiguration(
                    isEnabled: false, assignModel: "claude-sonnet-5-5", summaryModel: "claude-opus-5-5",
                    effort: "medium", languageCode: reloaded.languageCode, claudePath: "/tools/claude"))
    }

    @Test func ignoresEmptyModelsAndUnknownEfforts() {
        defaults.set("", forKey: "assignModel")
        defaults.set("extreme", forKey: "aiEffort")
        let preferences = Preferences(defaults: defaults)
        #expect(preferences.assignModel == "claude-haiku-5-5")
        #expect(preferences.aiEffort == "low")
    }

    @Test func namesLanguagesInEnglish() {
        #expect(OutputLanguage.name(of: "cs") == "Czech")
        #expect(OutputLanguage.name(of: "de") == "German")
        #expect(OutputLanguage.nativeName(of: "cs") == "čeština")
        #expect(OutputLanguage.choices.contains("cs"))
        #expect(!OutputLanguage.systemCode.isEmpty)
    }
}
