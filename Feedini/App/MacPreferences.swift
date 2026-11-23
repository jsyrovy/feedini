import Foundation
import Observation

/// The preferences of the Mac app on top of the shared ones (`shared`), in the same `UserDefaults`: the menu bar, AI,
/// backups and the update check.
@MainActor
@Observable
final class MacPreferences {
    private static let showsUnreadCountKey = "showsUnreadCount"
    private static let aiEnabledKey = "aiEnabled"
    private static let claudePathKey = "claudePath"
    private static let assignModelKey = "assignModel"
    private static let summaryModelKey = "summaryModel"
    private static let aiEffortKey = "aiEffort"
    private static let summaryLanguageKey = "summaryLanguage"
    private static let singleArticleSummariesKey = "singleArticleSummaries"
    private static let backsUpKey = "backsUp"
    private static let backupFrequencyKey = "backupFrequency"
    private static let checksForUpdatesKey = "checksForUpdates"
    private static let syncsKey = "syncsWithICloud"

    /// The preferences of both apps.
    let shared: Preferences

    /// Whether the menu bar item shows the number of unread stories. On by default.
    var showsUnreadCount: Bool {
        didSet {
            defaults.set(showsUnreadCount, forKey: Self.showsUnreadCountKey)
        }
    }

    /// The models offered in Settings → AI.
    static let modelChoices = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
    static let defaultModel = AIConfiguration.defaultModel
    static let effortChoices = ["low", "medium", "high"]
    static let defaultEffort = AIConfiguration.defaultEffort

    /// Whether new articles are organized (and summarized) by AI. On by default; without claude it says why.
    var aiEnabled: Bool {
        didSet {
            defaults.set(aiEnabled, forKey: Self.aiEnabledKey)
            onAIChange?()
        }
    }

    /// A path to `claude`; empty to look it up.
    var claudePath: String {
        didSet {
            defaults.set(claudePath, forKey: Self.claudePathKey)
            onAIChange?()
        }
    }

    var assignModel: String {
        didSet {
            defaults.set(assignModel, forKey: Self.assignModelKey)
            onAIChange?()
        }
    }

    var summaryModel: String {
        didSet {
            defaults.set(summaryModel, forKey: Self.summaryModelKey)
            onAIChange?()
        }
    }

    var aiEffort: String {
        didSet {
            defaults.set(aiEffort, forKey: Self.aiEffortKey)
            onAIChange?()
        }
    }

    /// The language code of AI titles, topics and summaries; empty for the system language.
    var summaryLanguage: String {
        didSet {
            defaults.set(summaryLanguage, forKey: Self.summaryLanguageKey)
            onAIChange?()
        }
    }

    /// Which single articles get an AI title and summary. None by default.
    var singleArticleSummaries: SingleArticleSummaries {
        didSet {
            defaults.set(singleArticleSummaries.rawValue, forKey: Self.singleArticleSummariesKey)
            onAIChange?()
        }
    }

    /// Whether the library and settings are backed up to iCloud Drive automatically. Off by default: the first backup
    /// makes macOS ask for access to iCloud Drive, which should happen when the user turned it on.
    var backsUp: Bool {
        didSet {
            defaults.set(backsUp, forKey: Self.backsUpKey)
            onBackupChange?()
        }
    }

    /// Daily by default.
    var backupFrequency: BackupFrequency {
        didSet {
            defaults.set(backupFrequency.rawValue, forKey: Self.backupFrequencyKey)
            onBackupChange?()
        }
    }

    /// Whether GitHub is asked for a newer release once a day. Off by default: the request tells GitHub the IP
    /// address, which the user should agree to.
    var checksForUpdates: Bool {
        didSet {
            defaults.set(checksForUpdates, forKey: Self.checksForUpdatesKey)
            onUpdatesChange?()
        }
    }

    /// The language code in effect.
    var summaryLanguageCode: String {
        summaryLanguage.isEmpty ? OutputLanguage.systemCode : summaryLanguage
    }

    /// The AI settings as the queues use them.
    var aiConfiguration: AIConfiguration {
        AIConfiguration(
            isEnabled: aiEnabled, assignModel: assignModel, summaryModel: summaryModel, effort: aiEffort,
            languageCode: summaryLanguageCode, claudePath: claudePath, singleArticleSummaries: singleArticleSummaries)
    }

    /// Whether the library syncs with other devices through iCloud. Off by default (like backups): turning it on
    /// uploads the library.
    var syncsWithICloud: Bool {
        didSet {
            defaults.set(syncsWithICloud, forKey: Self.syncsKey)
            onSyncChange?()
        }
    }

    /// What the list shows of the summaries (`AppModel.summarySettings`).
    var summarySettings: SummarySettings {
        SummarySettings(language: summaryLanguageCode, singleArticles: singleArticleSummaries)
    }

    /// Called after an AI preference changed.
    @ObservationIgnored var onAIChange: (@MainActor () -> Void)?

    /// Called after a backup preference changed.
    @ObservationIgnored var onBackupChange: (@MainActor () -> Void)?

    /// Called after `checksForUpdates` changed.
    @ObservationIgnored var onUpdatesChange: (@MainActor () -> Void)?

    /// Called after `syncsWithICloud` changed.
    @ObservationIgnored var onSyncChange: (@MainActor () -> Void)?

    @ObservationIgnored private var defaults: UserDefaults { shared.defaults }

    init(shared: Preferences = Preferences()) {
        self.shared = shared
        let defaults = shared.defaults
        // A value that isn't offered (none saved, or edited by hand) falls back to the default.
        showsUnreadCount = defaults.object(forKey: Self.showsUnreadCountKey) as? Bool ?? true
        aiEnabled = defaults.object(forKey: Self.aiEnabledKey) as? Bool ?? true
        claudePath = defaults.string(forKey: Self.claudePathKey) ?? ""
        assignModel = Self.model(defaults.string(forKey: Self.assignModelKey)) ?? Self.defaultModel
        summaryModel = Self.model(defaults.string(forKey: Self.summaryModelKey)) ?? Self.defaultModel
        aiEffort = Self.effort(defaults.string(forKey: Self.aiEffortKey)) ?? Self.defaultEffort
        summaryLanguage = Self.summaryLanguage(defaults.string(forKey: Self.summaryLanguageKey)) ?? ""
        singleArticleSummaries =
            defaults.string(forKey: Self.singleArticleSummariesKey).flatMap(SingleArticleSummaries.init(rawValue:))
            ?? AIConfiguration.defaultSingleArticleSummaries
        backsUp = defaults.bool(forKey: Self.backsUpKey)
        backupFrequency =
            defaults.string(forKey: Self.backupFrequencyKey).flatMap(BackupFrequency.init(rawValue:)) ?? .daily
        checksForUpdates = defaults.bool(forKey: Self.checksForUpdatesKey)
        syncsWithICloud = defaults.bool(forKey: Self.syncsKey)
    }
}

// The rules for stored values, also for those of a backup (`apply`): `nil` for a value that isn't valid.
extension MacPreferences {
    /// Model names are free text (new models appear), only empty ones aren't valid.
    static func model(_ name: String?) -> String? {
        name.flatMap { $0.isEmpty ? nil : $0 }
    }

    static func effort(_ effort: String?) -> String? {
        effort.flatMap { effortChoices.contains($0) ? $0 : nil }
    }

    /// A language code, or empty for the system language.
    static func summaryLanguage(_ language: String?) -> String? {
        language == "" ? "" : FeedLanguage.code(language)
    }
}
