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
                    // A story of one article in another language shows the AI's translated gist above its text.
                    ArticleDetail(article: article, story: entry.isMultiArticle ? nil : entry)
                }
            } else {
                StoryDetail(entry: entry)
            }
        } else {
            ContentUnavailableView(
                "No Selection", systemImage: "doc.text", description: Text("Press ? for keyboard shortcuts."))
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
                SummaryView(entry: entry)
                Divider()
                Text("Articles").font(.headline)
                ForEach(entry.articles) { article in
                    Button {
                        reader.visit(.article(entry.id, article.id))
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            UnreadDot(isUnread: !article.isRead)
                            if let source = model.library.sourceTitle(of: article) {
                                SourceLabel(title: source).font(.caption)
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

/// An article with the text from its feed, or a saved link with the text of its page.
struct ArticleDetail: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let article: Article
    /// The one-article story the article is shown for, if any (for its summary).
    var story: StoryEntry?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(article.title)
                    .font(.title.bold())
                    .textSelection(.enabled)
                Text(meta)
                    .foregroundStyle(.secondary)
                if let partOf = story?.partOf {
                    Text("Part of: \(partOf)")
                        .foregroundStyle(.secondary)
                }
                if article.isSavedLink {
                    Label(
                        "Saved link, added \(article.firstSeen.formatted(date: .abbreviated, time: .shortened))",
                        systemImage: "link"
                    )
                    .foregroundStyle(.secondary)
                }
                if let link = article.link {
                    HStack {
                        OpenButtons(url: link)
                        PageButtons(article: article)
                    }
                }
                // The page summary replaces the AI gist of the feed text: it is more complete.
                if PageSummaryView.isShown(for: article, status: model.aiStatus) {
                    PageSummaryView(article: article)
                } else if let story, story.needsSummary {
                    SummaryView(entry: story)
                }
                Divider()
                if article.isSavedLink {
                    LinkText(article: article, isStored: model.library.pageTextIDs.contains(article.id))
                } else if reader.previewArticle == article.id {
                    PagePreview(article: article, isStored: model.library.pageTextIDs.contains(article.id))
                } else {
                    Paragraphs(text: article.text.isEmpty ? "No text in the feed." : article.text)
                }
            }
            .padding(24)
            .frame(maxWidth: 760, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .id(article.id)
    }

    private var meta: String {
        let feed = model.library.sourceTitle(of: article)
        let date = article.published.map { $0.formatted(date: .abbreviated, time: .shortened) }
        return [feed, article.author, date].compactMap { $0 }.joined(separator: " · ")
    }
}

/// Plain text with paragraphs separated by blank lines.
struct Paragraphs: View {
    let text: String

    var body: some View {
        ForEach(Array(text.components(separatedBy: "\n\n").enumerated()), id: \.offset) { _, paragraph in
            if !paragraph.isEmpty {
                Text(paragraph)
                    .font(.body)
                    .lineSpacing(3)
                    .textSelection(.enabled)
            }
        }
    }
}

/// The text of the source page instead of the feed text (P), or how loading it goes.
struct PagePreview: View {
    @Environment(AppModel.self) private var model
    let article: Article
    /// Passed in, so the preview isn't drawn again on every change of the library.
    let isStored: Bool
    /// Read from its file once the text is stored (`ArticleDetail` gives every article a view of its own).
    @State private var text: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !isStored {
                PageLoadStatus(phase: model.aiStatus.pages[article.id]?.phase)
            } else if let text {
                Label("Text of the source page · P shows the feed text", systemImage: "doc.plaintext")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                PageTextBody(text: text)
            }
        }
        .task(id: isStored) {
            if isStored {
                text = await model.pageText(article.id)
                if text == nil {
                    // Its file was gone: load the page again.
                    model.loadPage(article.id)
                }
            }
        }
    }
}

/// Loading a page (also before the work started), or why it failed.
struct PageLoadStatus: View {
    let phase: AIStatus.PageWork.Phase?

    var body: some View {
        switch phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.secondary)
        case .loading, .summarizing, nil:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text("Loading page…")
            }
            .foregroundStyle(.secondary)
        }
    }
}

/// A page's text, with a pointer to V where it was cut.
struct PageTextBody: View {
    let text: String

    var body: some View {
        Paragraphs(text: text)
        if PageText.isTruncated(text) {
            Text("The text is cut off here. Press V for the whole page.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// "Preview" (P) – "Reload Page" on a saved link – and "Summarize Page" (T).
struct PageButtons: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    let article: Article

    var body: some View {
        if article.isSavedLink {
            Button("Reload Page", systemImage: "arrow.clockwise") { reader.reloadPage(article.id) }
                .help("P: load the page again, after accepting cookies or logging in with V")
                .disabled(model.aiStatus.pages[article.id]?.isRunning == true)
        } else {
            Toggle(
                "Preview", systemImage: "doc.plaintext",
                isOn: Binding(
                    get: { reader.previewArticle == article.id },
                    set: { _ in reader.togglePreview(article.id) })
            )
            .toggleStyle(.button)
            .help("P")
        }
        Button("Summarize Page", systemImage: "sparkles") { reader.summarizePage(article.id) }
            .help("T")
            .disabled(!model.canSummarizePage(article.id))
    }

}

/// The text of a saved link's page: it has no feed text. Its page loading (again) or why that failed shows above it,
/// unless the page summary shows it (T, or Save Link… with AI).
struct LinkText: View {
    @Environment(AppModel.self) private var model
    let article: Article
    /// Passed in, so the text isn't drawn again on every change of the library.
    let isStored: Bool
    /// Read from its file when stored, and again once the page was loaded again (P).
    @State private var text: String?

    var body: some View {
        let work = model.aiStatus.pages[article.id]
        let isLoading = work?.phase == .loading
        VStack(alignment: .leading, spacing: 14) {
            if let work, !work.summary {
                PageLoadStatus(phase: work.phase)
            }
            if let text, isStored {
                PageTextBody(text: text)
            } else if !isStored && !isLoading {
                Text("The text of the page isn't loaded. Press P to load it.")
                    .foregroundStyle(.secondary)
            }
        }
        .task(id: [isStored, isLoading]) {
            if isStored && !isLoading {
                text = await model.pageText(article.id)
            }
        }
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
                Button("Summarize Page", systemImage: "sparkles") { reader.summarizePage(article.id) }
                    .help("Back to the article with a summary of this page")
                Button("Open in Browser", systemImage: "safari") { reader.open(url, inWindow: false) }
            }
            .padding(8)
            .background(.bar)
            Divider()
            WebPageView(url: url) { reader.closePage() }
        }
    }
}
