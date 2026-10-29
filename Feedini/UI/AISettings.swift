import SwiftUI

/// AI: on / off, where claude is, models and effort, the latest calls.
struct AISettings: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        @Bindable var preferences = model.preferences
        Form {
            Section {
                Toggle("Organize and summarize articles with AI", isOn: $preferences.aiEnabled)
                LabeledContent("Status") {
                    AIStateLabel(state: model.aiStatus.state)
                }
            } footer: {
                Text(
                    "Uses the Claude Code CLI you are signed in to. Only the feed texts are sent, never web pages; reading never waits for AI."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section {
                Picker("Language", selection: $preferences.summaryLanguage) {
                    Text("System (\(OutputLanguage.nativeName(of: OutputLanguage.systemCode)))").tag("")
                    Divider()
                    ForEach(languages, id: \.self) { code in
                        Text("\(OutputLanguage.name(of: code)) (\(OutputLanguage.nativeName(of: code)))").tag(code)
                    }
                }
                Picker("Summarize single articles", selection: $preferences.singleArticleSummaries) {
                    Text("Never").tag(SingleArticleSummaries.never)
                    Text("In other languages").tag(SingleArticleSummaries.otherLanguages)
                    Text("Always").tag(SingleArticleSummaries.always)
                }
            } footer: {
                Text(
                    "Story titles, topics and summaries are written in this language. Stories with several articles always get a summary; a single article gets one only as chosen above (in other languages it is a translation), otherwise it shows its own title and text. After a change, summaries are rewritten gradually, unread stories first."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Section("claude") {
                TextField("Path", text: $claudePath, prompt: Text(detectedPath ?? "Not found"))
                    .onSubmit { preferences.claudePath = claudePath }
                Text(pathHint)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("Advanced") {
                ModelPicker(title: "Organizing model", selection: $preferences.assignModel)
                ModelPicker(title: "Summary model", selection: $preferences.summaryModel)
                Picker("Effort", selection: $preferences.aiEffort) {
                    ForEach(Preferences.effortChoices, id: \.self) { Text($0.capitalized).tag($0) }
                }
            }

            Section("Usage") {
                UsageSummary(usage: model.library.usage)
            }

            Section("Recent calls") {
                if model.aiStatus.calls.isEmpty {
                    Text("None yet").foregroundStyle(.secondary)
                } else {
                    ForEach(model.aiStatus.calls) { call in
                        CallRow(call: call)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { claudePath = model.preferences.claudePath }
        // A typed path is used once it is submitted or the settings close, not on every keystroke.
        .onDisappear { model.preferences.claudePath = claudePath }
        .task(id: model.preferences.claudePath) {
            let locator = ClaudeLocator()
            let saved = model.preferences.claudePath
            detectedPath = locator.locate()?.path
            if saved.isEmpty {
                pathHint =
                    detectedPath.map { "Found automatically: \($0)" }
                    ?? "claude wasn't found in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or PATH."
            } else {
                pathHint =
                    locator.locate(customPath: saved) == nil ? "This file isn't an executable." : "Using this path."
            }
        }
    }

    @State private var claudePath = ""
    @State private var detectedPath: String?
    @State private var pathHint = ""

    private var languages: [String] {
        let choices = OutputLanguage.choices.sorted {
            OutputLanguage.name(of: $0).localizedStandardCompare(OutputLanguage.name(of: $1)) == .orderedAscending
        }
        let saved = model.preferences.summaryLanguage
        return saved.isEmpty || choices.contains(saved) ? choices : choices + [saved]
    }
}

private struct ModelPicker: View {
    let title: String
    @Binding var selection: String

    var body: some View {
        Picker(title, selection: $selection) {
            ForEach(choices, id: \.self) { Text($0).tag($0) }
        }
    }

    /// The offered models plus a different one saved before.
    private var choices: [String] {
        Preferences.modelChoices.contains(selection) ? Preferences.modelChoices : Preferences.modelChoices + [selection]
    }
}

private struct AIStateLabel: View {
    let state: AIStatus.State

    var body: some View {
        switch state {
        case .idle: Label("Ready", systemImage: "checkmark.circle").foregroundStyle(.green)
        case .off: Label("Off", systemImage: "pause.circle").foregroundStyle(.secondary)
        case .organizing(let count): Label("Organizing \(count) articles…", systemImage: "sparkles")
        case .unavailable(let reason):
            Label(reason, systemImage: "exclamationmark.triangle").foregroundStyle(.orange).help(reason)
        }
    }
}

private struct CallRow: View {
    let call: AIStatus.Call

    var body: some View {
        HStack {
            Text(call.date.formatted(date: .omitted, time: .standard))
                .monospacedDigit()
                .foregroundStyle(.secondary)
            Text(call.step)
            Spacer()
            if let error = call.error {
                Text(error).foregroundStyle(.orange).lineLimit(1).help(error)
            } else if let stats = call.stats {
                Text(
                    "\(Double(stats.durationMs) / 1000, format: .number.precision(.fractionLength(1))) s · \(stats.costUSD, format: .currency(code: "USD").precision(.fractionLength(4)))"
                )
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .help(stats.model)
            }
        }
        .font(.callout)
    }
}

/// AI time and cost per day (the last 7 days) and in total (30 days).
private struct UsageSummary: View {
    let usage: [AIUsageDay]

    var body: some View {
        if usage.isEmpty {
            Text("No AI calls yet").foregroundStyle(.secondary)
        } else {
            ForEach(usage.suffix(7).reversed(), id: \.day) { day in
                LabeledContent(day.day) {
                    Text(Self.describe(day)).monospacedDigit()
                }
            }
            LabeledContent("Last \(usage.count) days") {
                Text(Self.describe(total)).monospacedDigit().fontWeight(.medium)
            }
        }
    }

    private var total: AIUsageDay {
        usage.reduce(into: AIUsageDay(day: "")) { total, day in
            total.calls += day.calls
            total.failures += day.failures
            total.durationMs += day.durationMs
            total.costUSD += day.costUSD
        }
    }

    private static func describe(_ day: AIUsageDay) -> String {
        let minutes = Double(day.durationMs) / 60_000
        var parts = [
            day.calls == 1 ? "1 call" : "\(day.calls) calls",
            minutes < 1
                ? "\(Int((Double(day.durationMs) / 1000).rounded())) s"
                : "\(minutes.formatted(.number.precision(.fractionLength(1)))) min",
            day.costUSD.formatted(.currency(code: "USD").precision(.fractionLength(2...3))),
        ]
        if day.failures > 0 {
            parts.append("\(day.failures) failed")
        }
        return parts.joined(separator: " · ")
    }
}
