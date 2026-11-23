import Foundation
import Testing

@testable import Feedini

extension ReaderTests {
    @Test func sSavesTheArticleUnderTheCursorAndAgainRemovesIt() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.save)
        #expect(model.library.articles[lone.id]?.isSaved == true)
        #expect(model.savedEntries().map(\.id) == [.savedArticle(lone.id)])
        #expect(model.unreadCounts.saved == 1)

        reader.handle(.save)
        #expect(model.library.articles[lone.id]?.isSaved == false)
        #expect(model.savedEntries().isEmpty)
    }

    @Test func sOnACollapsedStoryWithSeveralArticlesDoesNothing() {
        reader.visit(.story(.story(story.id)))

        #expect(!reader.handle(.save))
        reader.toggleSaved(.story(.story(story.id)))

        #expect(model.savedEntries().isEmpty)
        #expect(reader.undoName == "Mark as Read")
    }

    @Test func oldestFirstListsSavedFromTheFirstSaved() {
        model.setSaved(lone.id, at: .hours(-2))
        model.setSaved(first.id, at: .hours(-1))
        reader.selection = .saved
        #expect(reader.entries.map(\.id) == [.savedArticle(first.id), .savedArticle(lone.id)])

        model.preferences.listOrder = .oldestFirst

        #expect(reader.entries.map(\.id) == [.savedArticle(lone.id), .savedArticle(first.id)])
    }

    @Test func sOnAnArticleOfAnExpandedStorySavesTheArticleAndTheStoryShowsIt() {
        reader.visit(.article(.story(story.id), second.id))
        reader.handle(.save)

        #expect(model.library.articles[second.id]?.isSaved == true)
        #expect(model.entry(.savedArticle(second.id))?.title == "Second")
        #expect(model.entry(.story(story.id))?.containsSaved == true)
    }

    @Test func savedShowsSavedEntriesReadOrNotAndShiftADoesNothing() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.save)
        reader.selection = .saved

        #expect(reader.entries.map(\.id) == [.savedArticle(lone.id)])
        reader.visit(.story(.savedArticle(lone.id)))
        reader.handle(.markAllRead)
        #expect(reader.cursor == .story(.savedArticle(lone.id)))
        #expect(reader.entries.count == 1)
        #expect(model.library.articles[lone.id]?.isRead == true)
    }

    @Test func removingFromSavedKeepsTheEntryInItsPlaceUntilTheSelectionChanges() {
        model.setSaved(lone.id, at: .hours(-1))
        model.setSaved(first.id, at: .hours(-2))
        model.setSaved(second.id, at: .hours(-3))
        reader.selection = .saved
        let ids: [StoryEntry.ID] = [.savedArticle(lone.id), .savedArticle(first.id), .savedArticle(second.id)]
        #expect(reader.entries.map(\.id) == ids)

        reader.visit(.story(.savedArticle(first.id)))
        reader.handle(.save)
        reader.visit(.story(.savedArticle(second.id)))
        reader.handle(.save)

        #expect(model.savedEntries().map(\.id) == [.savedArticle(lone.id)])
        #expect(reader.entries.map(\.id) == ids)
        #expect(reader.entry(.savedArticle(first.id))?.articles.map(\.id) == [first.id])

        // S again saves it anew.
        reader.handle(.save)
        #expect(model.library.articles[second.id]?.isSaved == true)

        reader.selection = .all
        reader.selection = .saved
        #expect(reader.entries.map(\.id) == [.savedArticle(second.id), .savedArticle(lone.id)])
    }

    @Test func aRefreshKeepsOnlyTheEntryUnderTheCursor() {
        model.setSaved(lone.id, at: .hours(-1))
        model.setSaved(first.id, at: .hours(-2))
        reader.selection = .saved
        reader.visit(.story(.savedArticle(lone.id)))
        reader.handle(.save)
        reader.visit(.story(.savedArticle(first.id)))
        reader.handle(.save)

        model.onRefresh?()

        #expect(reader.entries.map(\.id) == [.savedArticle(first.id)])
    }

    @Test func removingAFeedKeepsItsSavedArticlesInSaved() {
        model.setSaved(lone.id, at: .hours(-1))
        model.removeFeeds([feed.id])

        #expect(model.library.articles.keys.map { $0 } == [lone.id])
        #expect(model.savedEntries().map(\.id) == [.savedArticle(lone.id)])
        #expect(model.library.sourceTitle(of: feed.id) == "Tech")
    }

    @Test func shiftSSavesAndPreparesTheSummaryWithoutLeavingTheDetail() async {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.open)
        reader.handle(.saveWithSummary)

        #expect(model.library.articles[lone.id]?.isSaved == true)
        #expect(reader.pageArticle == lone.id)
        #expect(model.pageStatus[lone.id]?.summary == true)
        await model.pageLoader.waitUntilIdle()
        #expect(extractor.requests == [lone.link!])

        // Shift+S never removes it from Saved.
        reader.handle(.saveWithSummary)
        #expect(model.library.articles[lone.id]?.isSaved == true)
        await model.pageLoader.waitUntilIdle()
    }

    @Test func shiftSOnAnArticleWithoutALinkOnlySavesIt() async {
        model.update { $0.articles[lone.id]?.link = nil }
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.saveWithSummary)

        #expect(model.library.articles[lone.id]?.isSaved == true)
        #expect(model.pageStatus.pages.isEmpty)
        await model.pageLoader.waitUntilIdle()
        #expect(extractor.requests.isEmpty)
    }

    @Test func shiftSOnAStoryWithSeveralArticlesDoesNothing() async {
        reader.visit(.story(.story(story.id)))
        #expect(!reader.handle(.saveWithSummary))
        reader.saveWithSummary(.story(.story(story.id)))

        #expect(model.savedEntries().isEmpty)
        #expect(model.pageStatus.pages.isEmpty)
        await model.pageLoader.waitUntilIdle()
        #expect(extractor.requests.isEmpty)
    }
}
