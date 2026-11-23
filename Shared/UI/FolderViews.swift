import SwiftUI

/// A folder to name: a new one (with the feeds to move into it) or an existing one to rename.
struct FolderNaming: Identifiable {
    let id = UUID()
    /// `nil` for a new folder.
    var folder: Folder.ID?
    /// The feeds a new folder takes in.
    var moving: Set<Feed.ID> = []
}

/// Asks for the name of a new folder, or a new name of a folder.
struct FolderNameSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    let naming: FolderNaming
    @State private var name = ""
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(naming.folder == nil ? "New Folder" : "Rename Folder").font(.headline)
            TextField("Name", text: $name)
                .textFieldStyle(.roundedBorder)
                .onSubmit(save)
            if let error {
                Label(error, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            HStack {
                Spacer()
                Button("Cancel") { dismiss() }.keyboardShortcut(.cancelAction)
                Button(naming.folder == nil ? "Create" : "Rename", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 320)
        .onAppear {
            name = naming.folder.flatMap { model.library.folder($0)?.name } ?? ""
        }
    }

    private func save() {
        do throws(FolderNameError) {
            if let folder = naming.folder {
                try model.renameFolder(folder, to: name)
            } else {
                try model.addFolder(named: name, moving: naming.moving)
            }
            dismiss()
        } catch {
            self.error = error.message
        }
    }
}

/// The items of a "Move to Folder" menu for feeds: no folder, every folder (the current one checked) and a new one.
/// The model is passed in, not read from the environment: context menus of tables and lists are built where it may be
/// missing.
struct MoveToFolderMenu: View {
    let model: AppModel
    let feeds: Set<Feed.ID>
    /// Asks for the name of a new folder for the feeds.
    let newFolder: (FolderNaming) -> Void

    var body: some View {
        let current = Set(feeds.map { model.library.feed($0)?.folderID })
        Menu("Move to Folder") {
            item("No Folder", folder: nil, current: current)
            if !model.library.folders.isEmpty {
                Divider()
                ForEach(model.library.folders) { folder in
                    item(folder.name, folder: folder.id, current: current)
                }
            }
            Divider()
            Button("New Folder…") { newFolder(FolderNaming(moving: feeds)) }
        }
        .disabled(feeds.isEmpty)
    }

    private func item(_ title: String, folder: Folder.ID?, current: Set<Folder.ID?>) -> some View {
        Toggle(
            title,
            isOn: Binding(
                get: { current == [folder] },
                set: { _ in model.moveFeeds(feeds, to: folder) }))
    }
}

/// Chooses a folder, or none. The folders are passed in, not read from the environment: table rows created while
/// scrolling don't get the model from it (reading it there crashes).
struct FolderPicker: View {
    let folders: [Folder]
    @Binding var selection: Folder.ID?

    var body: some View {
        Picker("Folder", selection: $selection) {
            Text("No Folder").tag(nil as Folder.ID?)
            ForEach(folders) { folder in
                Text(folder.name).tag(Optional(folder.id))
            }
        }
        .labelsHidden()
    }
}
