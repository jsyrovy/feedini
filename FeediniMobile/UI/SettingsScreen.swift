import SwiftUI

/// Settings: the feeds, how articles open, the order of the lists and how often feeds are refreshed.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var preferences = model.preferences
        NavigationStack {
            Form {
                Section {
                    NavigationLink {
                        FeedsScreen()
                    } label: {
                        LabeledContent("Feeds", value: "\(model.library.feeds.count)")
                    }
                }
                Section {
                    Picker("Open Pages In", selection: $preferences.pageOpening) {
                        Text("Feedini").tag(Preferences.PageOpening.window)
                        Text("Browser").tag(Preferences.PageOpening.browser)
                    }
                    ListOrderPicker(preferences: preferences)
                    Picker("Refresh Every", selection: $preferences.refreshMinutes) {
                        ForEach(Preferences.refreshMinutesChoices, id: \.self) { minutes in
                            Text(minutes == 60 ? "1 hour" : "\(minutes) minutes").tag(minutes)
                        }
                    }
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Feeds are refreshed while Feedini is open.")
                }
                Section {
                    LabeledContent("Version", value: Self.version)
                } footer: {
                    Text("Feedini for the Mac organizes articles into stories and summarizes them with AI.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private static var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "?"
    }
}

/// The feeds by folder with the state of their last download; adding by address, removing (confirmed), folders.
struct FeedsScreen: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    @State private var folder: Folder.ID?
    @State private var isAdding = false
    @State private var addError: String?
    @State private var removal: Removal?
    @State private var naming: FolderNaming?

    var body: some View {
        let library = model.library
        let feeds = Dictionary(grouping: library.feedsByTitle, by: \.folderID)
        List {
            Section {
                TextField("Address of a feed", text: $address)
                    .keyboardType(.URL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onSubmit(add)
                if !library.folders.isEmpty {
                    Picker("Folder", selection: $folder) {
                        Text("No Folder").tag(nil as Folder.ID?)
                        ForEach(library.folders) { folder in
                            Text(folder.name).tag(Optional(folder.id))
                        }
                    }
                }
                Button(isAdding ? "Adding…" : "Add Feed", action: add)
                    .disabled(isAdding || address.trimmingCharacters(in: .whitespaces).isEmpty)
                if let addError {
                    Text(addError).font(.footnote).foregroundStyle(.orange)
                }
            } footer: {
                Text("Only HTTPS feeds are supported.")
            }
            ForEach(library.folders) { folder in
                Section {
                    ForEach(feeds[folder.id] ?? []) { feed in
                        row(feed)
                    }
                } header: {
                    Text(folder.name)
                        .contextMenu {
                            Button("Rename…") { naming = FolderNaming(folder: folder.id) }
                            Button("Delete Folder…", role: .destructive) { removal = .folder(folder.id) }
                        }
                }
            }
            Section(library.folders.isEmpty ? "Feeds" : "No Folder") {
                ForEach(feeds[nil] ?? []) { feed in
                    row(feed)
                }
            }
        }
        .navigationTitle("Feeds")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("New Folder", systemImage: "folder.badge.plus") { naming = FolderNaming() }
            }
        }
        .removalConfirmation($removal, model: model)
        .sheet(item: $naming) { naming in
            FolderNameSheet(naming: naming)
                .presentationDetents([.height(180)])
        }
    }

    private func row(_ feed: Feed) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(feed.title)
            Text(state(of: feed))
                .font(.caption)
                .foregroundStyle(feed.lastError == nil ? Color.secondary : .orange)
                .lineLimit(2)
        }
        .swipeActions {
            Button("Remove", systemImage: "trash", role: .destructive) { removal = .feeds([feed.id]) }
        }
        .contextMenu {
            MoveToFolderMenu(model: model, feeds: [feed.id]) { naming = $0 }
            Button("Remove Feed…", role: .destructive) { removal = .feeds([feed.id]) }
        }
    }

    private func state(of feed: Feed) -> String {
        if let error = feed.lastError {
            return error
        }
        guard let checked = feed.lastChecked else { return feed.url.host() ?? feed.url.absoluteString }
        return RelativeTime.updated(checked, now: .now)
    }

    private func add() {
        let address = address
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty, !isAdding else { return }
        isAdding = true
        addError = nil
        Task {
            if let failure = await model.subscribe(to: address, folder: folder) {
                addError = failure.message
            } else {
                self.address = ""
            }
            isAdding = false
        }
    }
}
