import SwiftUI

/// A story's AI summary in the detail: the text (bullet points for big stories), "Summarizing…" while it is being
/// written, or why it couldn't be.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    @Environment(MacServices.self) private var mac
    let entry: StoryEntry

    var body: some View {
        if let summary = entry.summary {
            SummaryBox(spacing: 6) {
                SummaryText(text: summary.text)
                if !entry.isSummaryCurrent && mac.aiStatus.isWorking {
                    Label("Updating summary…", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } else if entry.needsSummary {
            status
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .story(let id) = entry.id, let error = mac.aiStatus.summaryErrors[id] {
            Label("No summary: \(error)", systemImage: "exclamationmark.triangle")
        } else {
            switch mac.aiStatus.state {
            case .off, .unavailable:
                EmptyView()
            case .idle, .organizing:
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small)
                    Text("Summarizing…")
                }
            }
        }
    }
}

/// The AI summary of an article's source page (T): the TL;DR as a paragraph and the details as bullet points,
/// "Loading page…" / "Summarizing page…" while T works, or why it failed.
struct PageSummaryView: View {
    @Environment(AppModel.self) private var model
    let article: Article

    /// When there is a summary, or T was asked for one.
    static func isShown(for article: Article, status: PageStatus) -> Bool {
        article.pageSummary != nil || status[article.id]?.summary == true
    }

    var body: some View {
        SummaryBox(title: "Page Summary") {
            if let summary = article.pageSummary {
                PageSummaryText(summary: summary)
            }
            if let work = model.pageStatus[article.id], work.summary {
                status(work.phase, isUpdating: article.pageSummary != nil)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func status(_ phase: PageStatus.Work.Phase, isUpdating: Bool) -> some View {
        switch phase {
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle")
        case .loading, .summarizing:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(phase == .loading ? "Loading page…" : isUpdating ? "Updating summary…" : "Summarizing page…")
            }
        }
    }
}
