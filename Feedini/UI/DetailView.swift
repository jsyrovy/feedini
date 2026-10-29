import SwiftUI

/// The detail of the row under the cursor: a story with several articles, an article's feed text, or its source page.
struct DetailView: View {
    @Environment(Reader.self) private var reader

    var body: some View {
        if let cursor = reader.cursor, let entry = reader.entry(cursor.entryID) {
            if let article = reader.cursorArticle {
                if reader.pageArticle == article.id, let link = article.link {
                    SourcePage(article: article, url: link)
                } else {
                    ArticleDetail(article: article)
                }
            } else {
                StoryDetail(entry: entry)
            }
        } else {
            ContentUnavailableView("No Selection", systemImage: "doc.text")
        }
    }
}

/// A story with several articles: its title and the list of its articles.
struct StoryDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let entry: StoryEntry

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(entry.title)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text("\(entry.feedIDs.count) sources · \(entry.articles.count) articles")
                    .foregroundStyle(.secondary)
                Divider()
                Text("Articles").font(.headline)
                ForEach(entry.articles) { article in
                    Button {
                        reader.visit(.article(entry.id, article.id))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            UnreadDot(isUnread: !article.isRead)
                            if let feed = model.library.feed(article.feedID) {
                                SourceLabel(title: feed.title).font(.caption)
                            }
                            Text(article.title)
                                .foregroundStyle(article.isRead ? .secondary : .primary)
                                .multilineTextAlignment(.leading)
                            Spacer(minLength: 0)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

/// An article with the text from its feed.
struct ArticleDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let article: Article

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(article.title)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text(meta)
                    .foregroundStyle(.secondary)
                if let link = article.link {
                    OpenButtons(url: link)
                }
                Divider()
                ForEach(Array(paragraphs.enumerated()), id: \.offset) { _, paragraph in
                    Text(paragraph)
                        .font(.body)
                        .lineSpacing(3)
                        .textSelection(.enabled)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(article.id)
    }

    private var meta: String {
        let feed = model.library.feed(article.feedID)?.title
        let date = article.published.map { $0.formatted(date: .abbreviated, time: .shortened) }
        return [feed, article.author, date].compactMap { $0 }.joined(separator: " · ")
    }

    private var paragraphs: [String] {
        let paragraphs = article.text.components(separatedBy: "\n\n").filter { !$0.isEmpty }
        return paragraphs.isEmpty ? ["No text in the feed."] : paragraphs
    }
}

/// "Open in Feedini" and "Open in Browser", the default way first.
struct OpenButtons: View {
    @Environment(Reader.self) private var reader
    let url: URL

    var body: some View {
        HStack {
            if reader.opensInWindow {
                windowButton.keyboardShortcut(.defaultAction)
                browserButton
            } else {
                browserButton.keyboardShortcut(.defaultAction)
                windowButton
            }
        }
        .controlSize(.regular)
    }

    private var windowButton: some View {
        Button("Open in Feedini", systemImage: "doc.richtext") { reader.open(url, inWindow: true) }
            .help(reader.opensInWindow ? "V / Enter" : "Shift+V / Shift+Enter")
    }

    private var browserButton: some View {
        Button("Open in Browser", systemImage: "safari") { reader.open(url, inWindow: false) }
            .help(reader.opensInWindow ? "Shift+V / Shift+Enter" : "V / Enter")
    }
}

/// An article's source page in the window, loaded only on the user's request.
struct SourcePage: View {
    @Environment(Reader.self) private var reader
    let article: Article
    let url: URL

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Button("Back to Article", systemImage: "chevron.left") { reader.closePage() }
                    .help("Esc")
                Spacer()
                Text(url.host() ?? url.absoluteString)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                Spacer()
                Button("Open in Browser", systemImage: "safari") { reader.open(url, inWindow: false) }
            }
            .padding(8)
            .background(.bar)
            Divider()
            WebPageView(url: url) { reader.closePage() }
        }
    }
}
