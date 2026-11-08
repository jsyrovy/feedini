import Foundation
import Testing

@testable import Feedini

extension ReaderTests {
    @Test func sSavesTheArticleOrTheStoryUnderTheCursorAndAgainRemovesIt() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.save)
        #expect(model.library.articles[lone.id]?.isSaved == true)

        reader.visit(.story(.story(story.id)))
        reader.handle(.save)
        #expect(model.library.stories[story.id]?.savedAt != nil)
        #expect(Set(model.savedEntries().map(\.id)) == [.story(story.id), .savedArticle(lone.id)])
        #expect(model.unreadCounts.saved == 2)

        reader.handle(.save)
        #expect(model.library.stories[story.id]?.savedAt == nil)
        #expect(model.savedEntries().map(\.id) == [.savedArticle(lone.id)])
    }

    @Test func oldestFirstListsSavedFromTheFirstSaved() {
        model.setSaved(.article(lone.id), at: .hours(-2))
        model.setSaved(.story(story.id), at: .hours(-1))
        reader.selection = .saved
        #expect(reader.entries.map(\.id) == [.story(story.id), .savedArticle(lone.id)])

        model.preferences.listOrder = .oldestFirst

        #expect(reader.entries.map(\.id) == [.savedArticle(lone.id), .story(story.id)])
    }

    @Test func sOnAnArticleOfAnExpandedStorySavesTheArticle() {
        reader.visit(.article(.story(story.id), second.id))
        reader.handle(.save)

        #expect(model.library.articles[second.id]?.isSaved == true)
        #expect(model.library.stories[story.id]?.savedAt == nil)
        #expect(model.entry(.savedArticle(second.id))?.partOf == "Story")
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
        model.setSaved(.article(lone.id), at: .hours(-1))
        model.setSaved(.article(first.id), at: .hours(-2))
        model.setSaved(.story(story.id), at: .hours(-3))
        reader.selection = .saved
        let ids: [StoryEntry.ID] = [.savedArticle(lone.id), .savedArticle(first.id), .story(story.id)]
        #expect(reader.entries.map(\.id) == ids)

        reader.visit(.story(.savedArticle(first.id)))
        reader.handle(.save)
        reader.visit(.story(.story(story.id)))
        reader.handle(.save)

        #expect(model.savedEntries().map(\.id) == [.savedArticle(lone.id)])
        #expect(reader.entries.map(\.id) == ids)
        #expect(reader.entry(.savedArticle(first.id))?.articles.map(\.id) == [first.id])

        // S again saves it anew.
        reader.handle(.save)
        #expect(model.library.stories[story.id]?.savedAt != nil)

        reader.selection = .all
        reader.selection = .saved
        #expect(reader.entries.map(\.id) == [.story(story.id), .savedArticle(lone.id)])
    }

    @Test func aRefreshKeepsOnlyTheEntryUnderTheCursor() {
        model.setSaved(.article(lone.id), at: .hours(-1))
        model.setSaved(.article(first.id), at: .hours(-2))
        reader.selection = .saved
        reader.visit(.story(.savedArticle(lone.id)))
        reader.handle(.save)
        reader.visit(.story(.savedArticle(first.id)))
        reader.handle(.save)

        model.onRefresh?()

        #expect(reader.entries.map(\.id) == [.savedArticle(first.id)])
    }

    @Test func removingAFeedKeepsItsSavedArticlesInSaved() {
        model.setSaved(.article(lone.id), at: .hours(-1))
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
        #expect(model.aiStatus.pages[lone.id]?.summary == true)
        await model.pageQueue?.waitUntilIdle()
        #expect(extractor.requests == [lone.link!])

        // Shift+S never removes it from Saved.
        reader.handle(.saveWithSummary)
        #expect(model.library.articles[lone.id]?.isSaved == true)
        await model.pageQueue?.waitUntilIdle()
    }

    @Test func shiftSOnAStoryWithSeveralArticlesOnlySavesIt() async {
        reader.visit(.story(.story(story.id)))
        reader.handle(.saveWithSummary)

        #expect(model.library.stories[story.id]?.savedAt != nil)
        #expect(model.aiStatus.pages.isEmpty)
        await model.pageQueue?.waitUntilIdle()
        #expect(extractor.requests.isEmpty)
    }
}
