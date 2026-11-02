import Foundation

/// What reading and saving change on some articles and stories: the state ⌘Z puts back.
struct ReadingState: Equatable, Sendable {
    struct ArticleState: Equatable, Sendable {
        var readAt: Date?
        var savedAt: Date?
    }

    struct StoryState: Equatable, Sendable {
        var savedAt: Date?
        /// Reading a story clears its "+1 new" marks.
        var newArticleIDs: Set<Article.ID>
    }

    var articles: [Article.ID: ArticleState] = [:]
    var stories: [Story.ID: StoryState] = [:]

    var isEmpty: Bool { articles.isEmpty && stories.isEmpty }
}

extension Library {
    /// The state of the articles and stories as it is now, with every story holding one of the articles (reading
    /// changes their "new" marks). Items that don't exist are left out.
    func readingState(
        articles articleIDs: some Sequence<Article.ID>, stories storyIDs: some Sequence<Story.ID> = []
    )
        -> ReadingState
    {
        var state = ReadingState()
        for id in articleIDs {
            if let article = articles[id] {
                state.articles[id] = ReadingState.ArticleState(readAt: article.readAt, savedAt: article.savedAt)
            }
        }
        var wanted = Set(storyIDs)
        for story in stories.values where story.articleIDs.contains(where: { state.articles[$0] != nil }) {
            wanted.insert(story.id)
        }
        for id in wanted {
            if let story = stories[id] {
                state.stories[id] = ReadingState.StoryState(savedAt: story.savedAt, newArticleIDs: story.newArticleIDs)
            }
        }
        return state
    }

    /// Puts the state back on the items that still exist; returns the state it replaced (empty when none exists).
    mutating func restore(_ state: ReadingState) -> ReadingState {
        let replaced = readingState(articles: state.articles.keys, stories: state.stories.keys)
        for (id, article) in state.articles where articles[id] != nil {
            articles[id]?.readAt = article.readAt
            articles[id]?.savedAt = article.savedAt
        }
        for (id, saved) in state.stories {
            guard var story = stories[id] else { continue }
            story.savedAt = saved.savedAt
            // Articles that left the story since can't be new in it.
            story.newArticleIDs = saved.newArticleIDs.intersection(story.articleIDs)
            stories[id] = story
        }
        return replaced
    }
}

/// The steps of reading and saving that ⌘Z takes back and ⇧⌘Z does again (pure). A new step clears what could be
/// done again; only the newest `limit` steps are kept.
struct UndoHistory: Sendable {
    struct Step: Equatable, Sendable {
        /// For the menu: "Undo Mark as Read".
        var name: String
        /// The state to put back.
        var state: ReadingState
        /// The row to show after the step was taken back or done again.
        var row: ListRow?
    }

    static let limit = 100

    private(set) var undoSteps: [Step] = []
    private(set) var redoSteps: [Step] = []

    var undoName: String? { undoSteps.last?.name }
    var redoName: String? { redoSteps.last?.name }

    mutating func record(_ step: Step) {
        undoSteps.append(step)
        if undoSteps.count > Self.limit {
            undoSteps.removeFirst(undoSteps.count - Self.limit)
        }
        redoSteps = []
    }

    /// Takes back the newest step: `apply` puts its state back and returns the state it replaced, or `nil` when none
    /// of its items exists anymore – then the step is dropped and the one before is tried. Returns the step taken back.
    mutating func undo(_ apply: (ReadingState) -> ReadingState?) -> Step? {
        Self.move(from: &undoSteps, to: &redoSteps, apply)
    }

    /// Does the step taken back last again, like `undo`.
    mutating func redo(_ apply: (ReadingState) -> ReadingState?) -> Step? {
        Self.move(from: &redoSteps, to: &undoSteps, apply)
    }

    private static func move(
        from source: inout [Step], to target: inout [Step], _ apply: (ReadingState) -> ReadingState?
    ) -> Step? {
        while let step = source.popLast() {
            if let replaced = apply(step.state) {
                target.append(Step(name: step.name, state: replaced, row: step.row))
                return step
            }
        }
        return nil
    }
}
