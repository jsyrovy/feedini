import Foundation
import Testing

@testable import Feedini

struct SampleLibraryTests {
    @Test func showsAStoryOfTwoFeedsASingleArticleStoryALooseArticleAndSaved() {
        let library = SampleLibrary.make(now: referenceDate)

        let entries = StoryList.allEntries(in: library, summaryLanguage: "en", singleArticles: .never)
            .compactMap { $0.visible(keeping: []) }
        #expect(
            entries.map(\.title) == [
                "Example Corp's foldable laptop ships in December for $2,999", "City opens a new tram line",
                "Researchers find water ice on a distant moon",
            ])
        #expect(entries[0].feedIDs.count == 2)
        #expect(entries[0].isSummaryCurrent)
        #expect(StoryList.savedEntries(in: library).map(\.title) == ["A long read about keyboards"])
        #expect(library.folders.map(\.name) == ["Reading"])
        #expect(library.folderIDsByFeed().count == 2)
    }
}
