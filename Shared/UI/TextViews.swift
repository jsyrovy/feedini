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
