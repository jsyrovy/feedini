import SwiftUI

/// The keyboard shortcuts (?), a sheet over the main window. Esc, ? or Done close it.
struct ShortcutsView: View {
    @Environment(AppModel.self) private var model
    @Environment(Reader.self) private var reader
    @Environment(\.dismiss) private var dismiss
    @FocusState private var isFocused: Bool

    var body: some View {
        let sections = ShortcutHelp.sections(
            opensInWindow: reader.opensInWindow, aiProblem: model.aiStatus.state.problem)
        VStack(alignment: .leading, spacing: 16) {
            Text("Keyboard Shortcuts")
                .font(.title2.bold())
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 16, verticalSpacing: 6) {
                ForEach(sections) { section in
                    GridRow {
                        Text(section.group.rawValue)
                            .font(.headline)
                            .padding(.top, 8)
                            .gridCellColumns(2)
                    }
                    ForEach(section.items) { item in
                        GridRow {
                            Text(item.keys)
                                .font(.body.monospaced())
                                .gridColumnAlignment(.trailing)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.description)
                                if let unavailable = item.unavailable {
                                    Text(unavailable).font(.caption)
                                }
                            }
                        }
                        .foregroundStyle(item.unavailable == nil ? .primary : .secondary)
                    }
                }
            }
            Text("The keys work in the story list. P and T work on an article, not on a story with several articles.")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
        }
        .padding(24)
        .frame(width: 540)
        .focusable()
        .focusEffectDisabled()
        .focused($isFocused)
        .onAppear { isFocused = true }
        .onExitCommand { dismiss() }
        .onKeyPress(characters: CharacterSet(charactersIn: "?"), phases: .down) { _ in
            dismiss()
            return .handled
        }
    }
}
