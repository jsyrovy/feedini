import Foundation
import Observation

/// User preferences, saved in `UserDefaults`.
@MainActor
@Observable
final class Preferences {
    private static let refreshMinutesKey = "refreshMinutes"
    private static let pageOpeningKey = "pageOpening"
    private static let showsUnreadCountKey = "showsUnreadCount"
    private static let aiEnabledKey = "aiEnabled"
    private static let claudePathKey = "claudePath"
    private static let assignModelKey = "assignModel"
    private static let summaryModelKey = "summaryModel"
    private static let aiEffortKey = "aiEffort"
    private static let summaryLanguageKey = "summaryLanguage"
    private static let singleArticleSummariesKey = "singleArticleSummaries"
    private static let collapsedFoldersKey = "collapsedFolders"
    private static let backsUpKey = "backsUp"
    private static let backupFrequencyKey = "backupFrequency"

    /// The choices for `refreshMinutes`.
    static let refreshMinutesChoices = [5, 15, 30, 60]
    static let defaultRefreshMinutes = 15

    /// Where V / Enter opens an article's source page; Shift+V / Shift+Enter uses the other place.
    enum PageOpening: String, CaseIterable, Sendable {
        case window, browser
    }

    /// Minutes between refreshes, one of `refreshMinutesChoices`.
    var refreshMinutes: Int {
        didSet {
            defaults.set(refreshMinutes, forKey: Self.refreshMinutesKey)
            onChange?()
        }
    }

    /// The Feedini window by default.
    var pageOpening: PageOpening {
        didSet {
            defaults.set(pageOpening.rawValue, forKey: Self.pageOpeningKey)
            onChange?()
        }
    }

    /// Whether the menu bar item shows the number of unread stories. On by default.
    var showsUnreadCount: Bool {
        didSet {
            defaults.set(showsUnreadCount, forKey: Self.showsUnreadCountKey)
        }
    }

    /// The folders collapsed in the sidebar (a window state, not data, so not in the library).
    var collapsedFolders: Set<Folder.ID> {
        didSet {
            defaults.set(collapsedFolders.map(\.uuidString).sorted(), forKey: Self.collapsedFoldersKey)
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

    /// Called after an AI preference changed.
    @ObservationIgnored var onAIChange: (@MainActor () -> Void)?

    /// Called after a preference changed.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    /// Called after a backup preference changed.
    @ObservationIgnored var onBackupChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A value that isn't offered (none saved, or edited by hand) falls back to the default.
        refreshMinutes =
            Self.refreshMinutes(defaults.integer(forKey: Self.refreshMinutesKey)) ?? Self.defaultRefreshMinutes
        pageOpening = defaults.string(forKey: Self.pageOpeningKey).flatMap(PageOpening.init(rawValue:)) ?? .window
        showsUnreadCount = defaults.object(forKey: Self.showsUnreadCountKey) as? Bool ?? true
        collapsedFolders = Set(
            (defaults.stringArray(forKey: Self.collapsedFoldersKey) ?? []).compactMap(UUID.init(uuidString:)))
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
    }
}

// The rules for stored values, also for those of a backup (`apply`): `nil` for a value that isn't valid.
extension Preferences {
    static func refreshMinutes(_ minutes: Int?) -> Int? {
        minutes.flatMap { refreshMinutesChoices.contains($0) ? $0 : nil }
    }

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
