import Testing

@testable import Feedini

struct FeedLanguageTests {
    @Test func reducesLanguageTagsToThePrimaryCode() {
        #expect(FeedLanguage.code("cs") == "cs")
        #expect(FeedLanguage.code(" cs-CZ ") == "cs")
        #expect(FeedLanguage.code("en_us") == "en")
        #expect(FeedLanguage.code("EN-gb") == "en")
        #expect(FeedLanguage.code("haw") == "haw")
        #expect(FeedLanguage.code(nil) == nil)
        #expect(FeedLanguage.code("") == nil)
        #expect(FeedLanguage.code("english") == nil)
        #expect(FeedLanguage.code("c1") == nil)
    }

    @Test func prefersTheFeedLanguage() {
        #expect(FeedLanguage.language(feedLanguage: "de", title: "Hello world", text: "This is English.") == "de")
    }

    @Test func detectsTheLanguageWithoutOne() {
        let czech = FeedLanguage.language(
            feedLanguage: nil, title: "Vláda schválila nový zákon o dopravě",
            text: "Poslanci budou o návrhu jednat příští týden, opozice s ním nesouhlasí.")
        #expect(czech == "cs")
        let english = FeedLanguage.language(
            feedLanguage: nil, title: "The government approved a new transport law",
            text: "Members of parliament will discuss the proposal next week.")
        #expect(english == "en")
    }

    @Test func givesNoLanguageWhenUnsure() {
        #expect(FeedLanguage.detect("") == nil)
        #expect(FeedLanguage.detect("1234 5678") == nil)
    }
}
