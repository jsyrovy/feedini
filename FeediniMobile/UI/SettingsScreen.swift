import SwiftUI
import UniformTypeIdentifiers

/// Settings: the feeds, how articles open, the order of the lists and how often feeds are refreshed.
struct SettingsScreen: View {
    @Environment(AppModel.self) private var model
    @Environment(MobileSync.self) private var sync
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
                } header: {
                    Text("Reading")
                } footer: {
                    Text("Feeds are refreshed when Feedini opens, then every 5 minutes. Pull down to refresh.")
                }
                SyncSection(sync: sync)
                Section {
                    LabeledContent("Version", value: RuntimeEnvironment.versionDescription)
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
    @State private var isImporting = false
    @State private var isImportRunning = false
    @State private var importReport: ImportReport?

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
                    FolderPicker(folders: library.folders, selection: $folder)
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
                Menu("More", systemImage: "ellipsis.circle") {
                    Button("New Folder…", systemImage: "folder.badge.plus") { naming = FolderNaming() }
                    Button("Import OPML…", systemImage: "square.and.arrow.down") { isImporting = true }
                        .disabled(isImportRunning)
                    if !model.library.feeds.isEmpty {
                        ShareLink(
                            "Export OPML", item: OPMLExport(data: model.exportOPML()),
                            preview: SharePreview("Feedini.opml"))
                    }
                }
            }
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: ImportReport.opmlTypes) { result in
            if case .success(let url) = result {
                importOPML(from: url)
            }
        }
        .sheet(item: $importReport) { report in
            ImportReportScreen(report: report)
        }
        .overlay {
            if isImportRunning {
                ProgressView("Checking the feeds…")
                    .padding()
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
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

    private func importOPML(from url: URL) {
        isImportRunning = true
        Task {
            importReport = await ImportReport.importing(from: url, into: model)
            isImportRunning = false
        }
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

/// What an OPML import added and what not, with the reason; the errors can be copied.
private struct ImportReportScreen: View {
    @Environment(\.dismiss) private var dismiss
    let report: ImportReport

    var body: some View {
        NavigationStack {
            List {
                if report.error != nil {
                    Label(report.summary, systemImage: "exclamationmark.triangle")
                } else {
                    Text(report.summary)
                    if !report.skipped.isEmpty {
                        Section("Not Added") {
                            ForEach(report.skipped, id: \.address) { SkippedFeedRow(item: $0) }
                        }
                    }
                }
            }
            .navigationTitle("OPML Import")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
                if let errorReport = report.errorReport {
                    ToolbarItem(placement: .bottomBar) {
                        Button("Copy Errors") { UIPasteboard.general.string = errorReport }
                    }
                }
            }
        }
    }
}

/// The feeds as an OPML file for the share sheet (Save to Files, AirDrop).
private struct OPMLExport: Transferable {
    let data: Data

    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(exportedContentType: UTType(filenameExtension: "opml") ?? .xml) { $0.data }
            .suggestedFileName("Feedini.opml")
    }
}

/// Sync with iCloud: on or off, its state, deleting the iCloud data.
private struct SyncSection: View {
    @Bindable var sync: MobileSync
    @State private var isConfirmingDeletion = false
    @State private var deletionError: String?

    var body: some View {
        let controller = sync.controller
        Section {
            Toggle("Sync with iCloud", isOn: $sync.isOn)
            LabeledContent("Status", value: status(controller.status))
            if let problem = controller.status.problem ?? deletionError {
                Text(problem).font(.footnote).foregroundStyle(.orange)
            }
            if controller.isRunning {
                Button("Delete iCloud Data…", role: .destructive) { isConfirmingDeletion = true }
            }
        } header: {
            Text("Sync")
        } footer: {
            Text(
                "Feeds, what you read and saved, and the stories and summaries from Feedini on the Mac, end-to-end "
                    + "encrypted with Advanced Data Protection.")
        }
        .confirmationDialog(
            "Delete the Feedini data in iCloud?", isPresented: $isConfirmingDeletion, titleVisibility: .visible
        ) {
            Button("Delete iCloud Data", role: .destructive) {
                Task {
                    do {
                        try await controller.deleteICloudData()
                        deletionError = nil
                    } catch {
                        deletionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text("The library stays on this iPhone. Sync turns off here and on your other devices.")
        }
    }

    private func status(_ status: SyncStatus) -> String {
        switch status {
        case .off: "Off"
        case .syncing: "Syncing…"
        case .synced(let date): date.map { "Synced \(RelativeTime.short($0, now: .now))" } ?? "On"
        case .unavailable, .failed, .needsUpdate: "Not syncing"
        }
    }
}
