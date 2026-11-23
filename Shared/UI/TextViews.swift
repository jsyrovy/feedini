import SwiftUI

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

/// Loading a page (also before the work started), or why it failed.
struct PageLoadStatus: View {
    let phase: PageStatus.Work.Phase?

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

/// A page's text, with a pointer to the whole page where it was cut.
struct PageTextBody: View {
    let text: String
    var cutNote = "The text is cut off here. Press V for the whole page."

    var body: some View {
        Paragraphs(text: text)
        if PageText.isTruncated(text) {
            Text(cutNote)
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}
