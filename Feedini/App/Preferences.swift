import Foundation
import Observation

/// User preferences, saved in `UserDefaults`.
@MainActor
@Observable
final class Preferences {
    private static let refreshMinutesKey = "refreshMinutes"
    private static let pageOpeningKey = "pageOpening"

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

    /// Called after a preference changed.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A value that isn't offered (none saved, or edited by hand) falls back to the default.
        let minutes = defaults.integer(forKey: Self.refreshMinutesKey)
        refreshMinutes = Self.refreshMinutesChoices.contains(minutes) ? minutes : Self.defaultRefreshMinutes
        pageOpening = defaults.string(forKey: Self.pageOpeningKey).flatMap(PageOpening.init(rawValue:)) ?? .window
    }
}
