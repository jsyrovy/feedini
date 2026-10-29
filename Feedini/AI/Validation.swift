import Foundation

/// Applies an assign answer to the library (pure), never trusting it:
///
/// - Unknown IDs are dropped; an article used twice stays where it was used first.
/// - New articles the answer left out get a story of their own (title of the article, no topic).
/// - A story's topic is the given topic id, a new topic's key, or – since models sometimes write the name instead –
///   an existing or new topic with that name (ignoring case); anything else becomes a new topic with that name.
/// - An article that joins a read story is marked new there ("+1 new"); the story comes back as unread.
enum AssignValidation {
    struct Metrics: Equatable, Sendable {
        var attached = 0
        var newStories = 0
        var newTopics = 0
        /// New articles the answer left out.
        var missing = 0
        /// IDs that weren't in the payload or were used twice.
        var unknownIDs = 0
        /// Topics referenced by something other than an id or key.
        var unresolvedTopics = 0
    }

    struct Result: Equatable, Sendable {
        var metrics = Metrics()
        /// Stories that got articles (new stories included): their summaries need (re)computing.
        var changedStories: [Story.ID] = []
    }

    /// `language` is the code new topics are written in.
    static func apply(
        _ output: AssignStep.Output, map: AssignStep.IDMap, language: String? = nil, to library: inout Library
    ) -> Result {
        var result = Result()
        var used = Set<Article.ID>()
        var changed: [Story.ID] = []

        func take(_ shortIDs: [String]) -> [Article.ID] {
            var ids: [Article.ID] = []
            for shortID in shortIDs {
                guard let id = map.articles[shortID], library.articles[id] != nil, used.insert(id).inserted else {
                    result.metrics.unknownIDs += 1
                    continue
                }
                ids.append(id)
            }
            return ids
        }

        for attachment in output.attach {
            guard let storyID = map.stories[attachment.storyID], let story = library.stories[storyID] else {
                result.metrics.unknownIDs += attachment.articleIDs.count
                continue
            }
            let ids = take(attachment.articleIDs)
            guard !ids.isEmpty else { continue }
            let wasRead = story.articleIDs.allSatisfy { library.articles[$0]?.isRead ?? true }
            library.stories[storyID]?.articleIDs += ids
            if wasRead || !story.newArticleIDs.isEmpty {
                library.stories[storyID]?.newArticleIDs.formUnion(ids)
            }
            result.metrics.attached += ids.count
            changed.append(storyID)
        }

        var topicsByKey: [String: Topic.ID] = [:]
        for newTopic in output.newTopics {
            let name = newTopic.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty, topicsByKey[newTopic.key] == nil else { continue }
            if let existing = topic(named: name, in: library) {
                topicsByKey[newTopic.key] = existing
                continue
            }
            let topic = Topic(name: name, description: newTopic.description, language: language)
            library.topics[topic.id] = topic
            topicsByKey[newTopic.key] = topic.id
            result.metrics.newTopics += 1
        }

        for newStory in output.newStories {
            let ids = take(newStory.articleIDs)
            guard !ids.isEmpty else { continue }
            let topicID = resolveTopic(
                newStory.topic, map: map, keys: topicsByKey, language: language, library: &library, result: &result)
            let title = newStory.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let story = Story(
                title: title.isEmpty ? library.articles[ids[0]]?.title ?? "" : title, topicID: topicID,
                articleIDs: ids)
            library.stories[story.id] = story
            result.metrics.newStories += 1
            changed.append(story.id)
        }

        for (_, id) in map.articles.sorted(by: { $0.key.localizedStandardCompare($1.key) == .orderedAscending })
        where !used.contains(id) && library.articles[id] != nil {
            let story = Story(title: library.articles[id]?.title ?? "", articleIDs: [id])
            library.stories[story.id] = story
            result.metrics.missing += 1
        }

        var seen = Set<Story.ID>()
        result.changedStories = changed.filter { seen.insert($0).inserted }
        return result
    }

    private static func resolveTopic(
        _ reference: String, map: AssignStep.IDMap, keys: [String: Topic.ID], language: String?,
        library: inout Library, result: inout Result
    ) -> Topic.ID? {
        let reference = reference.trimmingCharacters(in: .whitespacesAndNewlines)
        if let id = map.topics[reference] ?? keys[reference] {
            return id
        }
        guard !reference.isEmpty else { return nil }
        result.metrics.unresolvedTopics += 1
        if let id = topic(named: reference, in: library) {
            return id
        }
        let topic = Topic(name: reference, description: "", language: language)
        library.topics[topic.id] = topic
        result.metrics.newTopics += 1
        return topic.id
    }

    private static func topic(named name: String, in library: Library) -> Topic.ID? {
        library.topics.values.first { $0.name.caseInsensitiveCompare(name) == .orderedSame }?.id
    }
}
