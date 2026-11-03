import Foundation
import Testing

@testable import Feedini

struct PageMetadataTests {
    @Test func cleansWhatTheScriptReturns() {
        let metadata = PageMetadata(
            json: #"""
                {"title": " Ferry  Returns\n – Coastal Weekly ", "site": "Coastal Weekly",
                 "author": "https://social.example.com/someone", "published": "2026-10-30T07:15:00.250Z"}
                """#)
        #expect(metadata.title == "Ferry Returns")
        #expect(metadata.site == "Coastal Weekly")
        #expect(metadata.author == nil)
        #expect(metadata.published == Date(timeIntervalSince1970: 1_793_344_500.25))
    }

    @Test func leavesOutEmptyAndUnreadableValues() {
        #expect(PageMetadata(json: #"{"title": "  ", "site": null}"#) == PageMetadata())
        #expect(PageMetadata(json: "not json") == PageMetadata())
        // A title that is only the site's name stays.
        #expect(PageMetadata(json: #"{"title": "Weekly", "site": "Weekly"}"#).title == "Weekly")
        #expect(PageMetadata(json: #"{"title": "A | B", "site": "C"}"#).title == "A | B")
    }

    @Test func readsDatesWithOrWithoutTime() {
        #expect(PageMetadata.date("2026-10-30T08:15:00+01:00") == Date(timeIntervalSince1970: 1_793_344_500))
        #expect(PageMetadata.date(" 2026-10-30 ") == Date(timeIntervalSince1970: 1_793_318_400))
        #expect(PageMetadata.date("30 October 2026") == nil)
    }
}
