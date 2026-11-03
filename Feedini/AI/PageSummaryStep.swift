import Foundation

/// The page summary (T): a TL;DR of an article's source page, and details for longer texts (pure parts).
enum PageSummaryStep {
    /// Texts at least this long get details besides the TL;DR.
    static let detailsMinLength = 2_000

    static func wantsDetails(_ textLength: Int) -> Bool {
        textLength >= detailsMinLength
    }

    /// Written in the summary language. One in another language stays shown until T writes a new one.
    static func isCurrent(_ summary: PageSummary?, language: String) -> Bool {
        summary?.language == language
    }

    struct Input: Encodable, Equatable {
        var outputLanguage: String
        /// The feed's title, or a saved link's site.
        var source: String
        /// The title from the feed, so the AI can tell whether the page shows the article.
        var title: String
        var pageText: String

        private enum CodingKeys: String, CodingKey {
            case outputLanguage = "output_language", source, title
            case pageText = "page_text"
        }
    }

    struct Output: Decodable, Equatable, Sendable {
        enum Status: String, Decodable, Sendable {
            case ok
            /// A cookie consent or subscription wall, a login or error page, another article.
            case notArticle = "not_article"
        }

        var status: Status
        var tldr: String
        /// Missing in the schema for short texts.
        var details: [String]?
    }

    /// The request for the article's page text.
    static func request(
        for article: Article, pageText: String, in library: Library, configuration: AIConfiguration
    ) -> ClaudeRequest {
        let input = Input(
            outputLanguage: configuration.language, source: library.sourceTitle(of: article) ?? "",
            title: article.title, pageText: pageText)
        return ClaudeRequest(
            model: configuration.summaryModel, effort: configuration.effort, systemPrompt: Prompts.pageSummary,
            schema: wantsDetails(pageText.count) ? Prompts.pageSummarySchema : Prompts.pageSummaryTLDRSchema,
            payload: input)
    }

    enum Outcome: Equatable, Sendable {
        case summarized
        /// The page doesn't show the article; its stored text is dropped, so the next T loads the page again.
        case notArticle
        /// An empty TL;DR, or the article is gone.
        case empty
    }

    /// Stores the summary of an `ok` answer with a TL;DR.
    static func apply(
        _ output: Output, to articleID: Article.ID, language: String, date: Date, in library: inout Library
    ) -> Outcome {
        guard library.articles[articleID] != nil else { return .empty }
        guard output.status == .ok else {
            library.pageTextIDs.remove(articleID)
            return .notArticle
        }
        let tldr = output.tldr.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !tldr.isEmpty else { return .empty }
        // Short texts were asked for no details (`request`).
        let details = (output.details ?? []).map(cleanDetail).filter { !$0.isEmpty }
        library.articles[articleID]?.pageSummary = PageSummary(
            tldr: tldr, details: details, language: language, date: date)
        return .summarized
    }

    /// Without a bullet the model sometimes adds despite the prompt.
    private static func cleanDetail(_ detail: String) -> String {
        var detail = detail.trimmingCharacters(in: .whitespacesAndNewlines)
        if detail.hasPrefix("- ") || detail.hasPrefix("• ") {
            detail = detail.dropFirst(2).trimmingCharacters(in: .whitespaces)
        }
        return detail
    }
}
