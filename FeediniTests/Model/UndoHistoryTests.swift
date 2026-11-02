import Foundation
import Testing

@testable import Feedini

struct UndoHistoryTests {
    private let feed = Feed.stub("Tech")

    private func step(_ name: String) -> UndoHistory.Step {
        UndoHistory.Step(name: name, state: ReadingState(), row: nil)
    }

    @Test func undoAndRedoMoveStepsBetweenTheStacksWithTheReplacedState() {
        var history = UndoHistory()
        history.record(step("First"))
        history.record(step("Second"))
        #expect(history.undoName == "Second")
        #expect(history.redoName == nil)

        let replaced = ReadingState(articles: [UUID(): .init(readAt: .hours(1))])
        #expect(history.undo { _ in replaced }?.name == "Second")
        #expect(history.undoName == "First")
        #expect(history.redoSteps == [UndoHistory.Step(name: "Second", state: replaced, row: nil)])

        #expect(history.redo { state in state == replaced ? ReadingState() : nil }?.name == "Second")
        #expect(history.undoName == "Second")
        #expect(history.redoName == nil)
    }

    @Test func aNewStepClearsRedo() {
        var history = UndoHistory()
        history.record(step("First"))
        _ = history.undo { $0 }
        #expect(history.redoName == "First")

        history.record(step("Second"))
        #expect(history.redoName == nil)
    }

    @Test func stepsWhoseItemsAreGoneAreSkipped() {
        var history = UndoHistory()
        history.record(step("Kept"))
        history.record(step("Gone"))

        var calls = 0
        let undone = history.undo { state in
            calls += 1
            return calls == 1 ? nil : state
        }

        #expect(undone?.name == "Kept")
        #expect(history.undoSteps.isEmpty)
        #expect(history.redoSteps.map(\.name) == ["Kept"])
        #expect(history.undo { $0 } == nil)
    }

    @Test func keepsOnlyTheNewestSteps() {
        var history = UndoHistory()
        for index in 0..<(UndoHistory.limit + 5) {
            history.record(step("\(index)"))
        }
        #expect(history.undoSteps.count == UndoHistory.limit)
        #expect(history.undoSteps.first?.name == "5")
    }

    @Test func readingStateCoversTheStoriesOfTheArticlesAndRestoresTheirNewMarks() {
        let first = Article.stub(feed: feed.id, read: true)
        let second = Article.stub(feed: feed.id)
        let other = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [first.id, second.id], newArticleIDs: [second.id])
        let unrelated = Story(title: "Other", articleIDs: [other.id], savedAt: .hours(2))
        var library = Library(feeds: [feed], articles: [first, second, other], stories: [story, unrelated])

        let before = library.readingState(articles: [second.id, UUID()], stories: [unrelated.id, UUID()])
        #expect(Set(before.articles.keys) == [second.id])
        #expect(Set(before.stories.keys) == [story.id, unrelated.id])

        library.markRead([second.id], at: .hours(1))
        library.setSaved(.article(second.id), at: .hours(1))
        library.setSaved(.story(unrelated.id), at: nil)
        #expect(library.stories[story.id]?.newArticleIDs == [])

        let replaced = library.restore(before)

        #expect(library.articles[second.id]?.readAt == nil)
        #expect(library.articles[second.id]?.savedAt == nil)
        #expect(library.stories[story.id]?.newArticleIDs == [second.id])
        #expect(library.stories[unrelated.id]?.savedAt == .hours(2))
        #expect(replaced.articles[second.id] == .init(readAt: .hours(1), savedAt: .hours(1)))
        #expect(replaced.stories[unrelated.id]?.savedAt == nil)
    }

    @Test func restoringSkipsMissingItemsAndNewMarksOfArticlesThatLeft() {
        let article = Article.stub(feed: feed.id)
        let story = Story(title: "Story", articleIDs: [article.id])
        var library = Library(feeds: [feed], articles: [article], stories: [story])
        let state = ReadingState(
            articles: [UUID(): .init(readAt: .hours(1))],
            stories: [story.id: .init(newArticleIDs: [article.id, UUID()]), UUID(): .init(newArticleIDs: [])])

        _ = library.restore(state)

        #expect(library.stories[story.id]?.newArticleIDs == [article.id])
        #expect(library.articles.count == 1)
        #expect(library.readingState(articles: [UUID()]).isEmpty)
    }
}
