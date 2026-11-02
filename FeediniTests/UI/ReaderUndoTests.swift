import Foundation
import Testing

@testable import Feedini

extension ReaderTests {
    @Test func undoTakesBackReadingStepByStepAndShowsTheRowWithoutReadingIt() {
        model.update { $0.stories[story.id]?.newArticleIDs = [second.id] }
        reader.handle(.next)
        reader.handle(.next)
        #expect(isRead(lone) && isRead(first) && isRead(second))
        #expect(model.library.stories[story.id]?.newArticleIDs == [])
        #expect(reader.undoName == "Mark as Read")

        reader.undo()
        #expect(!isRead(first) && !isRead(second))
        #expect(model.library.stories[story.id]?.newArticleIDs == [second.id])
        #expect(reader.cursor == .story(.story(story.id)))
        #expect(isRead(lone))

        reader.undo()
        #expect(!isRead(lone))
        #expect(reader.cursor == .story(.loose(lone.id)))
        #expect(!isRead(lone))
        #expect(reader.undoName == nil)
        #expect(reader.redoName == "Mark as Read")

        reader.redo()
        #expect(isRead(lone))
        reader.redo()
        #expect(isRead(first) && isRead(second))
        #expect(reader.cursor == .story(.story(story.id)))
        #expect(reader.redoName == nil)
    }

    @Test func visitingAReadRowIsNoStep() {
        model.markRead([lone.id])
        reader.visit(.story(.loose(lone.id)))
        #expect(reader.undoName == nil)
    }

    @Test func undoOfAnArticleInAnExpandedStoryShowsTheArticle() {
        reader.visit(.article(.story(story.id), second.id))
        reader.visit(.story(.loose(lone.id)))
        reader.undo()
        reader.undo()

        #expect(!isRead(second))
        #expect(reader.cursor == .article(.story(story.id), second.id))
        #expect(reader.expanded.contains(.story(story.id)))
    }

    @Test func markAllReadIsOneStepAndUndoBringsTheEntriesBack() {
        reader.handle(.markAllRead)
        #expect(reader.entries.isEmpty)
        #expect(reader.undoName == "Mark All as Read")

        reader.undo()

        #expect(!isRead(lone) && !isRead(first) && !isRead(second))
        #expect(reader.entries.count == 2)
        #expect(reader.cursor == .story(.loose(lone.id)))
    }

    @Test func mAndSavingAreStepsToo() {
        reader.visit(.story(.loose(lone.id)))
        reader.handle(.toggleRead)
        #expect(reader.undoName == "Mark as Unread")
        reader.handle(.save)
        #expect(reader.undoName == "Save")

        reader.undo()
        #expect(model.library.articles[lone.id]?.isSaved == false)
        reader.undo()
        #expect(isRead(lone))

        reader.handle(.save)
        reader.handle(.save)
        #expect(reader.undoName == "Remove from Saved")
        reader.undo()
        #expect(model.library.articles[lone.id]?.isSaved == true)
    }

    @Test func shiftSIsASaveStepOnlyWhenItSaves() async {
        reader.visit(.story(.story(story.id)))
        reader.handle(.saveWithSummary)
        #expect(reader.undoName == "Save")
        reader.handle(.saveWithSummary)
        #expect(reader.history.undoSteps.count == 2)

        reader.undo()
        #expect(model.library.stories[story.id]?.savedAt == nil)
    }

    @Test func undoInSavedPutsTheItemBackInItsPlace() {
        model.setSaved(.article(lone.id), at: .hours(-1))
        model.setSaved(.article(first.id), at: .hours(-2))
        reader.selection = .saved
        reader.visit(.story(.savedArticle(first.id)))
        reader.handle(.save)
        reader.visit(.story(.savedArticle(lone.id)))

        reader.undo()
        reader.undo()

        #expect(model.library.articles[first.id]?.savedAt == .hours(-2))
        #expect(reader.cursor == .story(.savedArticle(first.id)))
    }

    @Test func undoSkipsStepsOfRemovedArticlesAndDoesNotMoveToAnotherSelection() {
        let other = Feed.stub("News")
        let news = Article.stub("News", feed: other.id)
        model.update {
            $0.feeds.append(other)
            $0.articles[news.id] = news
        }
        reader.visit(.story(.loose(lone.id)))
        reader.visit(.story(.loose(news.id)))
        model.removeFeeds([other.id])
        reader.selection = .feed(feed.id)
        reader.handle(.next)
        reader.selection = .all
        reader.selection = .feed(UUID())

        reader.undo()
        #expect(!isRead(first))
        #expect(reader.cursor == nil)

        reader.undo()
        #expect(!isRead(lone))
        #expect(reader.undoName == nil)
    }
}
