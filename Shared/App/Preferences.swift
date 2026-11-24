import Foundation
import Observation

/// The preferences of both apps, saved in `UserDefaults`; the Mac adds its own (`MacPreferences`).
@MainActor
@Observable
final class Preferences {
    private static let refreshMinutesKey = "refreshMinutes"
    private static let pageOpeningKey = "pageOpening"
    private static let articleViewKey = "articleView"
    private static let collapsedFoldersKey = "collapsedFolders"
    private static let listOrderKey = "listOrder"

    /// The choices for `refreshMinutes`.
    static let refreshMinutesChoices = [5, 15, 30, 60]
    static let defaultRefreshMinutes = 15

    /// Where V / Enter opens an article's source page; Shift+V / Shift+Enter uses the other place.
    enum PageOpening: String, CaseIterable, Sendable {
        case window, browser
    }

    /// What the detail shows on an article the user moves onto: the text from its feed, the text of its source page
    /// (as P) or the source page itself (as V in the window). The other views load the page on every article.
    enum ArticleView: String, CaseIterable, Sendable {
        case feedText, pageText, webPage
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

    /// The feed text by default: loading a page on every article is the user's choice.
    var articleView: ArticleView {
        didSet {
            defaults.set(articleView.rawValue, forKey: Self.articleViewKey)
            onChange?()
        }
    }

    /// The folders collapsed in the sidebar (a window state, not data, so not in the library).
    var collapsedFolders: Set<Folder.ID> {
        didSet {
            defaults.set(collapsedFolders.map(\.uuidString).sorted(), forKey: Self.collapsedFoldersKey)
        }
    }

    /// The order of the story list, newest first by default (a window state, not in backups).
    var listOrder: ListOrder {
        didSet {
            defaults.set(listOrder.rawValue, forKey: Self.listOrderKey)
        }
    }

    /// Called after a preference changed.
    @ObservationIgnored var onChange: (@MainActor () -> Void)?

    @ObservationIgnored let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        // A value that isn't offered (none saved, or edited by hand) falls back to the default.
        refreshMinutes =
            Self.refreshMinutes(defaults.integer(forKey: Self.refreshMinutesKey)) ?? Self.defaultRefreshMinutes
        pageOpening = defaults.string(forKey: Self.pageOpeningKey).flatMap(PageOpening.init(rawValue:)) ?? .window
        articleView =
            defaults.string(forKey: Self.articleViewKey).flatMap(ArticleView.init(rawValue:)) ?? .feedText
        collapsedFolders = Set(
            (defaults.stringArray(forKey: Self.collapsedFoldersKey) ?? []).compactMap(UUID.init(uuidString:)))
        listOrder = defaults.string(forKey: Self.listOrderKey).flatMap(ListOrder.init(rawValue:)) ?? .newestFirst
    }
}

// The rules for stored values, also for those of a backup: `nil` for a value that isn't valid.
extension Preferences {
    static func refreshMinutes(_ minutes: Int?) -> Int? {
        minutes.flatMap { refreshMinutesChoices.contains($0) ? $0 : nil }
    }
}

extension Preferences.ArticleView {
    /// The views an article can switch between on iOS: a saved link has no feed text, an article without a link no
    /// page.
    static func choices(for article: Article) -> [Self] {
        if article.link == nil {
            [.feedText]
        } else if article.isSavedLink {
            [.pageText, .webPage]
        } else {
            allCases
        }
    }

    /// What an opened article shows first on iOS: this view, or the first one it has.
    func shown(for article: Article) -> Self {
        let choices = Self.choices(for: article)
        return choices.contains(self) ? self : choices[0]
    }
}
