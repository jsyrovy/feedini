import Foundation
import Testing

@testable import Feedini

/// A story shows only its unread articles, and those read while the list is shown.
extension ReaderTests {
    private var storyID: StoryEntry.ID { .story(story.id) }

    @Test func articlesReadDuringAVisitStayUntilARefreshThenOnlyUnreadOnesShow() {
        reader.visit(.article(storyID, first.id))
        reader.visit(.story(.loose(lone.id)))

        // Nothing changes while the list is shown.
        #expect(reader.entry(storyID)?.articles.map(\.id) == [first.id, second.id])
        #expect(reader.rows.contains(.article(storyID, first.id)))

        model.onRefresh?()

        let entry = reader.entry(storyID)
        #expect(entry?.articles.map(\.id) == [second.id])
        #expect(entry?.title == "Second")
        #expect(entry?.isMultiArticle == false)
        // Expanded before, but with one article there is nothing to expand.
        #expect(reader.rows == [.story(.loose(lone.id)), .story(storyID)])
        #expect(model.unreadCounts.all == 1)
    }

    @Test func aRefreshKeepsWhatTheEntryUnderTheCursorShows() {
        reader.visit(.article(storyID, first.id))
        reader.handle(.next)
        #expect(reader.cursor == .article(storyID, second.id))

        model.onRefresh?()

        #expect(reader.entry(storyID)?.articles.map(\.id) == [first.id, second.id])
        #expect(reader.rows.contains(.article(storyID, second.id)))
        #expect(reader.entries.map(\.id) == [.loose(lone.id), storyID])
    }

    @Test func undoBringsBackAnArticleThatLeftItsStory() {
        reader.visit(.article(storyID, first.id))
        reader.visit(.story(.loose(lone.id)))
        model.onRefresh?()
        #expect(reader.entry(storyID)?.articles.count == 1)

        reader.undo()
        reader.undo()

        #expect(!isRead(first) && !isRead(lone))
        #expect(reader.entry(storyID)?.articles.map(\.id) == [first.id, second.id])
        #expect(reader.cursor == .article(storyID, first.id))

        // Done again, it stays in the story until the next refresh.
        reader.redo()
        #expect(isRead(first))
        #expect(reader.entry(storyID)?.articles.count == 2)
    }

    @Test func aStoryShowingOneArticleBehavesLikeAnArticle() async {
        model.markRead([first.id])
        let entry = reader.entry(storyID)
        #expect(entry?.articles.map(\.id) == [second.id])
        #expect(entry?.title == "Second")

        reader.visit(.story(storyID))
        #expect(reader.cursorArticle?.id == second.id)
        #expect(!reader.handle(.expand))
        reader.handle(.save)
        #expect(model.library.articles[second.id]?.isSaved == true)
        #expect(model.library.articles[first.id]?.isSaved == false)
        reader.handle(.preview)
        #expect(reader.previewArticle == second.id)
        await model.pageLoader.waitUntilIdle()
    }

    @Test func mTogglesTheArticlesTheStoryShows() {
        model.markRead([first.id])
        reader.visit(.article(.loose(lone.id), lone.id))
        reader.toggleRead(.story(storyID))
        #expect(isRead(second))
        #expect(reader.entry(storyID)?.articles.map(\.id) == [second.id])

        reader.toggleRead(.story(storyID))
        #expect(!isRead(second))
        // The article read before stays read and hidden.
        #expect(isRead(first))
        #expect(reader.entry(storyID)?.articles.map(\.id) == [second.id])
    }

    @Test func theCursorFollowsAnArticleIntoAStoryThatShowsOnlyIt() {
        model.markRead([second.id])
        reader.visit(.story(.loose(first.id)))
        let story = Story(title: "Story", articleIDs: [first.id, second.id])

        model.update { $0.stories = [story.id: story] }

        #expect(reader.cursor == .story(.story(story.id)))
        #expect(!reader.expanded.contains(.story(story.id)))
        #expect(reader.entry(.story(story.id))?.articles.map(\.id) == [first.id])
    }

    @Test func aStoryIsInAFeedOnlyWithAnArticleOfItThatItShows() {
        let other = Feed.stub("News")
        let news = Article.stub("News", feed: other.id, hours: -4)
        model.update {
            $0.feeds.append(other)
            $0.articles[news.id] = news
            $0.stories[story.id]?.articleIDs.append(news.id)
        }
        model.markRead([news.id])

        reader.selection = .feed(other.id)
        #expect(reader.entries.isEmpty)
        #expect(model.unreadCounts.count(for: .feed(other.id)) == 0)

        reader.selection = .feed(feed.id)
        #expect(reader.entries.map(\.id) == [.loose(lone.id), storyID])
        #expect(reader.entry(storyID)?.feedIDs == [feed.id])
    }
}
