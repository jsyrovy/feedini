import AppKit
import SwiftUI

/// Save Link… (+ in the toolbar, File → Save Link…, the menu bar): saves a web page into Saved by its address, offered
/// from the clipboard. It closes at once; the page loads in the background.
struct SaveLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var problem: String?
    @FocusState private var isFocused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Save Link")
                .font(.headline)
            Text("The page goes to Saved, with its text and, with AI, a TL;DR.")
                .foregroundStyle(.secondary)
            TextField("Address", text: $address, prompt: Text("https://…"))
                .labelsHidden()
                .focused($isFocused)
                .onSubmit(save)
                .onChange(of: address) { problem = nil }
            if let problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.secondary)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
        .onAppear {
            address = SavedLink.offeredAddress(NSPasteboard.general.string(forType: .string)) ?? ""
            isFocused = true
        }
    }

    private func save() {
        do {
            if case .alreadySaved = try model.saveLink(address) {
                problem = "This page is in Saved already."
                return
            }
            dismiss()
        } catch {
            problem = error.message
        }
    }
}

/// Opens the main window with Save Link… (File menu, menu bar).
struct SaveLinkButton: View {
    let reader: Reader
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        Button("Save Link…") {
            AppDelegate.mainWindowIsOpen(true)
            openWindow(id: FeediniApp.mainWindowID)
            reader.isShowingSaveLink = true
        }
        .keyboardShortcut("l")
    }
}
