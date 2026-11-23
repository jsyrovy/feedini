import Foundation

/// What decides the summaries a list shows: the language they must be in and which single articles get one. Set on
/// the Mac (Settings → AI); elsewhere the defaults apply.
struct SummarySettings: Equatable, Sendable {
    /// The code of the summary language (`cs`).
    var language = OutputLanguage.systemCode
    var singleArticles = SingleArticleSummaries.never
}
