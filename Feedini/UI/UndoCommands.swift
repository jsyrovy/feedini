import AppKit
import SwiftUI

/// Edit → Undo / Redo. In the main window ⌘Z and ⇧⌘Z take back and do again reading and saving (`Reader`);
/// elsewhere – Settings, sheets and their text fields – they go to the responder chain as usual.
struct UndoCommands: View {
    let reader: Reader

    var body: some View {
        if reader.isMainWindowKey {
            Button(reader.undoName.map { "Undo \($0)" } ?? "Undo") { reader.undo() }
                .keyboardShortcut("z")
                .disabled(reader.undoName == nil)
            Button(reader.redoName.map { "Redo \($0)" } ?? "Redo") { reader.redo() }
                .keyboardShortcut("z", modifiers: [.command, .shift])
                .disabled(reader.redoName == nil)
        } else {
            Button("Undo") { NSApp.sendAction(Selector(("undo:")), to: nil, from: nil) }
                .keyboardShortcut("z")
            Button("Redo") { NSApp.sendAction(Selector(("redo:")), to: nil, from: nil) }
                .keyboardShortcut("z", modifiers: [.command, .shift])
        }
    }
}
