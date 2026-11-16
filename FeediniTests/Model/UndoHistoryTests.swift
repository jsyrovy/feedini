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

    @Test func readingStateCoversTheArticlesAndRestoresThem() {
        let first = Article.stub(feed: feed.id, read: true)
        let second = Article.stub(feed: feed.id)
        var library = Library(feeds: [feed], articles: [first, second])

        let before = library.readingState(articles: [second.id, UUID()])
        #expect(Set(before.articles.keys) == [second.id])

        library.markRead([second.id], at: .hours(1))
        library.setSaved(second.id, at: .hours(1))

        let replaced = library.restore(before)

        #expect(library.articles[second.id]?.readAt == nil)
        #expect(library.articles[second.id]?.savedAt == nil)
        #expect(library.articles[first.id]?.isRead == true)
        #expect(replaced.articles[second.id] == .init(readAt: .hours(1), savedAt: .hours(1)))
    }

    @Test func restoringSkipsMissingArticles() {
        let article = Article.stub(feed: feed.id)
        var library = Library(feeds: [feed], articles: [article])

        let replaced = library.restore(ReadingState(articles: [UUID(): .init(readAt: .hours(1))]))

        #expect(replaced.isEmpty)
        #expect(library.articles == [article.id: article])
        #expect(library.readingState(articles: [UUID()]).isEmpty)
    }
}
