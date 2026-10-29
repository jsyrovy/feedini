import SwiftUI

/// A story's AI summary in the detail: the text (bullet points for big stories), "Summarizing…" while it is being
/// written, or why it couldn't be.
struct SummaryView: View {
    @Environment(AppModel.self) private var model
    let entry: StoryEntry

    var body: some View {
        if let summary = entry.summary {
            VStack(alignment: .leading, spacing: 6) {
                SummaryText(text: summary.text)
                if !entry.isSummaryCurrent && model.aiStatus.isWorking {
                    Label("Updating summary…", systemImage: "sparkles")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
        } else if entry.needsSummary {
            status
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        if case .story(let id) = entry.id, let error = model.aiStatus.summaryErrors[id] {
            Label("No summary: \(error)", systemImage: "exclamationmark.triangle")
        } else {
            switch model.aiStatus.state {
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

/// Summary text: sentences as a paragraph, lines starting with "- " as bullet points.
struct SummaryText: View {
    let text: String

    var body: some View {
        let lines = text.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if lines.contains(where: { $0.hasPrefix("- ") || $0.hasPrefix("• ") }) {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("•")
                        Text(line.hasPrefix("- ") || line.hasPrefix("• ") ? String(line.dropFirst(2)) : line)
                    }
                }
            }
            .textSelection(.enabled)
        } else {
            Text(text)
                .lineSpacing(3)
                .textSelection(.enabled)
        }
    }
}

/// The AI summary of an article's source page (T): the TL;DR as a paragraph and the details as bullet points,
/// "Loading page…" / "Summarizing page…" while T works, or why it failed.
struct PageSummaryView: View {
    @Environment(AppModel.self) private var model
    let article: Article

    /// When there is a summary, or T was asked for one.
    static func isShown(for article: Article, status: AIStatus) -> Bool {
        article.pageSummary != nil || status.pages[article.id]?.summary == true
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Page Summary", systemImage: "sparkles")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let summary = article.pageSummary {
                Text(summary.tldr)
                    .lineSpacing(3)
                    .textSelection(.enabled)
                if !summary.details.isEmpty {
                    SummaryText(text: summary.details.map { "- \($0)" }.joined(separator: "\n"))
                }
            }
            if let work = model.aiStatus.pages[article.id], work.summary {
                status(work.phase, isUpdating: article.pageSummary != nil)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    @ViewBuilder
    private func status(_ phase: AIStatus.PageWork.Phase, isUpdating: Bool) -> some View {
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
