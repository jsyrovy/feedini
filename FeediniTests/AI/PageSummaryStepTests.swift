import Foundation
import Testing

@testable import Feedini

struct PageSummaryStepTests {
    private let feed = Feed.stub("Tech")
    private let configuration = AIConfiguration(summaryModel: "claude-sonnet-5-5", effort: "medium", languageCode: "cs")
    private let article: Article

    init() {
        article = Article.stub("Launch", feed: feed.id)
    }

    private func payload(_ request: ClaudeRequest) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: request.input) as? [String: Any])
    }

    @Test func detailsStartAtTwoThousandCharacters() {
        #expect(!PageSummaryStep.wantsDetails(1_999))
        #expect(PageSummaryStep.wantsDetails(2_000))
    }

    @Test func aSummaryIsCurrentInTheSummaryLanguage() {
        let summary = PageSummary(tldr: "T", details: [], language: "cs", date: referenceDate)
        #expect(PageSummaryStep.isCurrent(summary, language: "cs"))
        #expect(!PageSummaryStep.isCurrent(summary, language: "en"))
        #expect(!PageSummaryStep.isCurrent(nil, language: "cs"))
    }

    @Test func requestCarriesTheFeedTitleAndThePageText() throws {
        let library = Library(feeds: [feed], articles: [article])

        let request = PageSummaryStep.request(
            for: article, pageText: "Short page text.", in: library, configuration: configuration)

        #expect(request.model == "claude-sonnet-5-5")
        #expect(request.effort == "medium")
        #expect(request.systemPrompt == Prompts.pageSummary)
        #expect(request.schema == Prompts.pageSummaryTLDRSchema)
        let payload = try payload(request)
        #expect(payload["output_language"] as? String == "Czech")
        #expect(payload["source"] as? String == "Tech")
        #expect(payload["title"] as? String == "Launch")
        #expect(payload["page_text"] as? String == "Short page text.")
    }

    @Test func aSavedLinkSendsItsSiteAsTheSource() throws {
        var link = Article.stub("Essay", feed: SavedLink.feedID)
        link.site = "Example Magazine"
        let request = PageSummaryStep.request(
            for: link, pageText: "Text.", in: Library(feeds: [feed], articles: [link]), configuration: configuration)
        #expect(try payload(request)["source"] as? String == "Example Magazine")
    }

    @Test func longTextsGetTheSchemaWithDetails() throws {
        let library = Library(feeds: [feed], articles: [article])
        let request = PageSummaryStep.request(
            for: article, pageText: String(repeating: "a", count: 2_000), in: library, configuration: configuration)
        #expect(request.schema == Prompts.pageSummarySchema)
    }

    @Test func storesAnOKAnswerWithDetailsForLongTexts() {
        var library = Library(feeds: [feed], articles: [article])
        let output = PageSummaryStep.Output(
            status: .ok, tldr: "  The gist. ", details: ["- First", "• Second", "Third", "  "])

        let outcome = PageSummaryStep.apply(output, to: article.id, language: "cs", date: referenceDate, in: &library)

        #expect(outcome == .summarized)
        #expect(
            library.articles[article.id]?.pageSummary
                == PageSummary(
                    tldr: "The gist.", details: ["First", "Second", "Third"], language: "cs", date: referenceDate))
    }

    @Test func notAnArticleDropsThePageText() {
        var library = Library(feeds: [feed], articles: [article])
        library.pageTextIDs = [article.id]
        let output = PageSummaryStep.Output(status: .notArticle, tldr: "", details: [])

        let outcome = PageSummaryStep.apply(output, to: article.id, language: "cs", date: referenceDate, in: &library)

        #expect(outcome == .notArticle)
        #expect(library.pageTextIDs.isEmpty)
        #expect(library.articles[article.id]?.pageSummary == nil)
    }

    @Test func anEmptyAnswerOrAGoneArticleStoresNothing() {
        var library = Library(feeds: [feed], articles: [article])
        let empty = PageSummaryStep.Output(status: .ok, tldr: " ", details: nil)

        #expect(
            PageSummaryStep.apply(empty, to: article.id, language: "cs", date: referenceDate, in: &library) == .empty)
        #expect(library.articles[article.id]?.pageSummary == nil)
        let ok = PageSummaryStep.Output(status: .ok, tldr: "Gist.", details: nil)
        #expect(PageSummaryStep.apply(ok, to: UUID(), language: "cs", date: referenceDate, in: &library) == .empty)
    }

    @Test func decodesBothSchemas() throws {
        let full = try JSONDecoder().decode(
            PageSummaryStep.Output.self, from: Data(#"{"status":"ok","tldr":"Gist.","details":["A"]}"#.utf8))
        #expect(full == PageSummaryStep.Output(status: .ok, tldr: "Gist.", details: ["A"]))
        let short = try JSONDecoder().decode(
            PageSummaryStep.Output.self, from: Data(#"{"status":"not_article","tldr":""}"#.utf8))
        #expect(short == PageSummaryStep.Output(status: .notArticle, tldr: "", details: nil))
    }
}
