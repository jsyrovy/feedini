import Foundation
import Observation

/// User preferences, saved in `UserDefaults`.
@MainActor
@Observable
final class Preferences {
    private static let refreshMinutesKey = "refreshMinutes"
    private static let pageOpeningKey = "pageOpening"
    private static let aiEnabledKey = "aiEnabled"
    private static let claudePathKey = "claudePath"
    private static let assignModelKey = "assignModel"
    private static let summaryModelKey = "summaryModel"
    private static let aiEffortKey = "aiEffort"

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

    /// The models offered in Settings → AI.
    static let modelChoices = ["claude-haiku-5-5", "claude-sonnet-5-5", "claude-opus-5-5"]
    static let defaultModel = "claude-haiku-5-5"
    static let effortChoices = ["low", "medium", "high"]
    static let defaultEffort = "low"

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

    /// The AI settings as the queues use them.
    var aiConfiguration: AIConfiguration {
        AIConfiguration(
            isEnabled: aiEnabled, assignModel: assignModel, summaryModel: summaryModel, effort: aiEffort,
            language: OutputLanguage.name(of: OutputLanguage.systemCode), claudePath: claudePath)
    }

    /// Called after an AI preference changed.
    @ObservationIgnored var onAIChange: (@MainActor () -> Void)?

    /// Called after a preference changed.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A value that isn't offered (none saved, or edited by hand) falls back to the default.
        let minutes = defaults.integer(forKey: Self.refreshMinutesKey)
        refreshMinutes = Self.refreshMinutesChoices.contains(minutes) ? minutes : Self.defaultRefreshMinutes
        pageOpening = defaults.string(forKey: Self.pageOpeningKey).flatMap(PageOpening.init(rawValue:)) ?? .window
        aiEnabled = defaults.object(forKey: Self.aiEnabledKey) as? Bool ?? true
        claudePath = defaults.string(forKey: Self.claudePathKey) ?? ""
        // Model names are free text (new models appear), only empty ones fall back.
        assignModel =
            defaults.string(forKey: Self.assignModelKey).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultModel
        summaryModel =
            defaults.string(forKey: Self.summaryModelKey).flatMap { $0.isEmpty ? nil : $0 } ?? Self.defaultModel
        let effort = defaults.string(forKey: Self.aiEffortKey) ?? ""
        aiEffort = Self.effortChoices.contains(effort) ? effort : Self.defaultEffort
    }
}
