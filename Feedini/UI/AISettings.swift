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

            Section("claude") {
                TextField("Path", text: $preferences.claudePath, prompt: Text(detectedPath ?? "Not found"))
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
    }

    private var detectedPath: String? {
        ClaudeLocator().locate()?.path
    }

    private var pathHint: String {
        if model.preferences.claudePath.isEmpty {
            return detectedPath.map { "Found automatically: \($0)" }
                ?? "claude wasn't found in ~/.local/bin, /opt/homebrew/bin, /usr/local/bin or PATH."
        }
        return ClaudeLocator().locate(customPath: model.preferences.claudePath) == nil
            ? "This file isn't an executable." : "Using this path."
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
