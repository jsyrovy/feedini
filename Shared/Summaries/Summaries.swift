import Foundation

/// Which stories with a single article get an AI title and summary (Settings → AI).
enum SingleArticleSummaries: String, CaseIterable, Codable, Sendable {
    /// None: a single article shows its own title and text.
    case never
    /// Articles in another language than the summary language (the summary is a translated gist).
    case otherLanguages
    /// Every article.
    case always
}

/// The summary step: a title and a summary for stories where they add something.
///
/// A summary is written from the unread articles of a story only: it is needed when there are several, for a single
/// one only as `singleArticles` says (without one, a single article shows its own text). Reading some of them doesn't
/// make it out of date; an unread article it doesn't cover does. What the list needs to know is shared; the work is
/// done on the Mac (`Feedini/AI/SummaryStep.swift`).
enum SummaryStep {
    /// An unknown article language counts as the summary language.
    static func needsSummary(
        _ articles: [Article], language: String, singleArticles: SingleArticleSummaries
    ) -> Bool {
        guard let article = articles.first else { return false }
        if articles.count > 1 { return true }
        switch singleArticles {
        case .never: return false
        case .otherLanguages: return article.language != nil && article.language != language
        case .always: return true
        }
    }

    /// Written in the language and covering every unread article (`articles` may hold read ones too, they don't
    /// count).
    static func isCurrent(_ summary: Summary?, of articles: [Article], language: String) -> Bool {
        guard let summary, summary.language == language else { return false }
        // A story has a few articles: searching beats hashing.
        return articles.allSatisfy { $0.isRead || summary.articleIDs.contains($0.id) }
    }
}
