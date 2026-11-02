import SwiftUI

/// A story (or a loose article) in the list.
struct StoryRow: View {
    @Environment(AppModel.self) private var model
    let entry: StoryEntry
    let isExpanded: Bool
    let toggleExpanded: () -> Void

    var body: some View {
        let sources = entry.feedIDs.compactMap(model.library.sourceTitle)
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            UnreadDot(isUnread: !entry.isRead)
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    if entry.isMultiArticle {
                        Button(action: toggleExpanded) {
                            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                                .font(.caption.weight(.semibold))
                                .frame(width: 10)
                        }
                        .buttonStyle(.plain)
                        .foregroundStyle(.secondary)
                    }
                    Text(entry.title)
                        .fontWeight(entry.isRead ? .regular : .semibold)
                        .foregroundStyle(entry.isRead ? .secondary : .primary)
                        .lineLimit(3)
                }
                HStack(spacing: 4) {
                    if sources.count > 1 {
                        ForEach(Array(sources.prefix(3).enumerated()), id: \.offset) { _, source in
                            SourceLabel(title: source)
                        }
                        if sources.count > 3 {
                            Text("+\(sources.count - 3)")
                        }
                    }
                    Text(meta(sources: sources))
                        .lineLimit(1)
                    if !entry.newArticleIDs.isEmpty {
                        Text("+\(entry.newArticleIDs.count) new")
                            .foregroundStyle(Color.accentColor)
                            .fontWeight(.semibold)
                    }
                    if isWaitingForAI {
                        Image(systemName: "sparkles")
                            .foregroundStyle(.tertiary)
                            .help("Not organized yet")
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
        .padding(.leading, 4)
        .overlay(alignment: .leading) {
            if sources.count > 1 {
                // Stories covered by several sources stand out.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(Color.accentColor)
                    .frame(width: 3)
                    .padding(.vertical, 2)
                    .offset(x: -6)
            }
        }
    }

    /// A loose article the AI is about to organize.
    private var isWaitingForAI: Bool {
        guard case .loose = entry.id else { return false }
        if case .organizing = model.aiStatus.state { return true }
        return false
    }

    private func meta(sources: [String]) -> String {
        let age = RelativeTime.short(entry.date, now: .now)
        guard entry.isMultiArticle else {
            return [sources.first, age].compactMap { $0 }.joined(separator: " · ")
        }
        var parts: [String] = []
        if sources.count > 1 {
            parts.append("\(sources.count) sources")
        }
        parts += ["\(entry.articles.count) articles", age]
        return parts.joined(separator: " · ")
    }
}

/// An article of an expanded story, indented under it.
struct ArticleRow: View {
    @Environment(AppModel.self) private var model
    let article: Article
    let isNew: Bool

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            UnreadDot(isUnread: !article.isRead)
            VStack(alignment: .leading, spacing: 2) {
                Text(article.title)
                    .foregroundStyle(article.isRead ? .secondary : .primary)
                    .lineLimit(2)
                HStack(spacing: 4) {
                    if let source = model.library.sourceTitle(of: article.feedID) {
                        SourceLabel(title: source)
                    }
                    Text(RelativeTime.short(article.date, now: .now))
                    if isNew {
                        Text("new").foregroundStyle(Color.accentColor).fontWeight(.semibold)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.leading, 22)
        .padding(.vertical, 2)
    }
}

struct UnreadDot: View {
    let isUnread: Bool

    var body: some View {
        Circle()
            .fill(isUnread ? Color.accentColor : .clear)
            .frame(width: 7, height: 7)
            .accessibilityLabel(isUnread ? "Unread" : "")
    }
}

/// A feed's name in a small capsule.
struct SourceLabel: View {
    let title: String

    var body: some View {
        Text(title)
            .lineLimit(1)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(.quaternary, in: Capsule())
    }
}
