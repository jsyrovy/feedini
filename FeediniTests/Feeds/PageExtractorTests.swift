import Foundation
import Testing
import WebKit

@testable import Feedini

struct PageTextTests {
    @Test func collapsesWhitespaceAndDropsEmptyParagraphs() {
        let raw =
            "  First   line \r\n\t second line\n\n\n\n \n\nNext paragraph " + String(repeating: "word ", count: 20)
        #expect(
            PageText.clean(raw)
                == "First line\nsecond line\n\nNext paragraph " + String(repeating: "word ", count: 19) + "word")
    }

    @Test func shortTextsAreNoText() {
        #expect(PageText.clean("Page not found\n\nSorry.") == nil)
        #expect(PageText.clean(String(repeating: "a", count: PageText.minLength)) != nil)
    }

    @Test func longTextsAreCut() throws {
        let text = try #require(PageText.clean(String(repeating: "word ", count: 30_000)))
        #expect(text.count == PageText.maxLength)
        #expect(text.hasSuffix("…"))
        #expect(PageText.isTruncated(text))
        #expect(!PageText.isTruncated(String(repeating: "word ", count: 100) + "…"))
    }

    @Test func errorMessages() {
        #expect(PageError.http(status: 404).message == "The server answered with HTTP 404 (not found).")
        #expect(PageError.timedOut.message == "The page didn't load in time.")
        #expect(PageError.noText.message == "The page has no readable text.")
        #expect(PageError.loadFailed("offline").message == "The page couldn't be loaded: offline")
    }
}

/// The extraction script in a real (hidden) web view, over made-up pages.
@MainActor
struct PageExtractorTests {
    private let extractor = PageExtractor(dataStore: .nonPersistent(), settleDelay: .zero, timeout: .seconds(20))

    private func extract(_ fixture: String) async throws -> String {
        try await content(fixture).text
    }

    private func content(_ fixture: String) async throws -> PageContent {
        let html = try #require(String(data: Fixture.data(fixture), encoding: .utf8))
        return try await extractor.extract(html: html, baseURL: URL(string: "https://example.com/article")!)
    }

    @Test func leavesOutACookieConsentOverlay() async throws {
        let text = try await extract("page-consent.html")
        #expect(text.hasPrefix("Harbor Town Opens a Floating Library\n\nThe small harbor town"))
        #expect(text.hasSuffix("concerts and school trips."))
        #expect(!text.contains("partners"))
        #expect(!text.contains("Home"))
    }

    @Test func readsBlocksOfAnArticleInDivs() async throws {
        let text = try await extract("page-div.html")
        #expect(
            text == """
                The Quiet Keyboard Company Ships Its First Model

                A two-person workshop called Quiet Keyboard has shipped its first mechanical keyboard after a year of \
                delays. The keyboard uses felt-lined switches that the founders designed themselves.

                The first batch of nine hundred units sold out in an hour. A second batch is planned for the spring, \
                with a numeric keypad that many buyers asked for.
                Prices start at 149 euros.

                What is inside

                • Felt-lined switches with a travel of 3.2 mm
                • An aluminium case made in a local foundry
                • Firmware that can be changed without special tools

                The founders say they will publish the design files of the case once the second batch ships, so that \
                others can make spare parts.

                layout: compact
                switches: felt
                """)
    }

    @Test func leavesOutMenusNavigationAndFooterOfMain() async throws {
        let text = try await extract("page-main.html")
        #expect(text.hasPrefix("Mountain Hut Gets a Solar Roof\n\nThe highest mountain hut"))
        #expect(text.hasSuffix("four weekends on the roof."))
        for noise in ["ARTICLES", "Read more", "Previous article", "Contact the editors"] {
            #expect(!text.contains(noise))
        }
    }

    @Test func fallsBackToJSONLDWhenThePageHasNoText() async throws {
        let text = try await extract("page-jsonld.html")
        #expect(text.hasPrefix("The river ferry between Oldbridge and Newbridge"))
    }

    @Test func aPageWithoutAnArticleHasNoText() async throws {
        await #expect(throws: PageError.noText) {
            _ = try await extract("page-empty.html")
        }
    }

    @Test func loadsAPageByItsAddress() async throws {
        let data = try Fixture.data("page-main.html")
        let url = try #require(URL(string: "data:text/html;base64,\(data.base64EncodedString())"))
        let text = try await extractor.extract(url).text
        #expect(text.hasPrefix("Mountain Hut Gets a Solar Roof"))
    }

    @Test func readsWhatThePageSaysAboutItself() async throws {
        let content = try await content("page-meta.html")
        #expect(content.text.hasPrefix("Lighthouse Keeper Retires After Forty Years\n\nThe keeper"))
        // An empty og:title gives way to <title>, without the site's name; the meta tags win over JSON-LD.
        #expect(
            content.metadata
                == PageMetadata(
                    title: "Lighthouse Keeper Retires After Forty Years", site: "The Coastal Weekly",
                    author: "Mara Lindqvist", published: Date(timeIntervalSince1970: 1_793_344_500)))
    }

    @Test func readsJSONLDWithoutMetaTags() async throws {
        let metadata = try await content("page-jsonld.html").metadata
        #expect(metadata.title == "River Ferry Returns")
        #expect(metadata.site == nil)
        #expect(metadata.published == nil)
    }

    @Test func givesUpAfterTheTimeout() async throws {
        let html = try #require(String(data: Fixture.data("page-div.html"), encoding: .utf8))
        let slow = PageExtractor(dataStore: .nonPersistent(), settleDelay: .seconds(60), timeout: .milliseconds(300))
        await #expect(throws: PageError.timedOut) {
            _ = try await slow.extract(html: html, baseURL: URL(string: "https://example.com/article")!)
        }
    }
}
