import SwiftUI
import UniformTypeIdentifiers

/// Feeds: the list with the folder and the state of the last download, adding by address (into a folder), moving
/// between folders, removing, OPML import and export.
struct FeedsSettings: View {
    @Environment(AppModel.self) private var model
    @State private var address = ""
    /// The folder a new feed goes into.
    @State private var folder: Folder.ID?
    @State private var naming: FolderNaming?
    @State private var isAdding = false
    @State private var addError: String?
    @State private var selection = Set<Feed.ID>()
    @State private var isConfirmingRemoval = false
    @State private var isImporting = false
    @State private var isImportRunning = false
    @State private var importReport: ImportReport?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                TextField("Feed address", text: $address, prompt: Text("https://example.com/feed.xml"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(add)
                    .disabled(isAdding)
                // A fixed width: a picker sized to fit grows with the longest folder name.
                FolderPicker(folders: model.library.folders, selection: $folder)
                    .frame(width: 150)
                    .help("The folder new feeds go into")
                    .disabled(isAdding)
                Button("Add", action: add)
                    .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty || isAdding)
                if isAdding {
                    ProgressView().controlSize(.small)
                }
            }
            if let addError {
                Label(addError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                    .font(.callout)
            }
            Table(feeds, selection: $selection) {
                TableColumn("Title") { feed in
                    Text(feed.title).help(feed.url.absoluteString)
                }
                TableColumn("Folder") { feed in
                    FolderPicker(
                        folders: model.library.folders,
                        selection: Binding(
                            get: { feed.folderID }, set: { model.moveFeeds([feed.id], to: $0) }))
                }
                .width(min: 90, ideal: 130)
                TableColumn("Status") { feed in
                    FeedStatus(feed: feed)
                }
            }
            .contextMenu(forSelectionType: Feed.ID.self) { ids in
                MoveToFolderMenu(model: model, feeds: ids) { naming = $0 }
                Divider()
                Button("Remove…") {
                    selection = ids
                    isConfirmingRemoval = true
                }
                .disabled(ids.isEmpty)
            }
            .onDeleteCommand { isConfirmingRemoval = !selection.isEmpty }
            HStack {
                Button("Remove…", systemImage: "minus") { isConfirmingRemoval = true }
                    .disabled(selection.isEmpty)
                Button("New Folder…") { naming = FolderNaming() }
                Spacer()
                if isImportRunning {
                    ProgressView().controlSize(.small)
                    Text("Checking feeds…").foregroundStyle(.secondary)
                }
                Button("Import OPML…") { isImporting = true }
                    .disabled(isImportRunning)
                Button("Export OPML…", action: export)
                    .disabled(model.library.feeds.isEmpty)
            }
            Text("Only HTTPS feeds are supported. An http:// address is tried over HTTPS.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .confirmationDialog(removalTitle, isPresented: $isConfirmingRemoval) {
            Button("Remove", role: .destructive) {
                model.removeFeeds(selection)
                selection = []
            }
        } message: {
            Text("Their articles are removed too.")
        }
        .fileImporter(isPresented: $isImporting, allowedContentTypes: Self.opmlTypes) { result in
            guard case .success(let url) = result else { return }
            importOPML(from: url)
        }
        .sheet(item: $importReport) { report in
            ImportReportView(report: report)
        }
        .sheet(item: $naming) { naming in
            FolderNameSheet(naming: naming)
        }
        .onChange(of: model.library.folders) {
            if let folder, model.library.folder(folder) == nil {
                self.folder = nil
            }
        }
    }

    private var feeds: [Feed] {
        model.library.feedsByTitle
    }

    private var removalTitle: String {
        selection.count == 1
            ? "Remove “\(model.library.feed(selection.first!)?.title ?? "")”?" : "Remove \(selection.count) feeds?"
    }

    private static let opmlTypes: [UTType] = [UTType(filenameExtension: "opml") ?? .xml, .xml]

    private func add() {
        let address = address
        guard !address.trimmingCharacters(in: .whitespaces).isEmpty else { return }
        isAdding = true
        addError = nil
        Task {
            let failure = await model.subscribe(to: address, folder: folder)
            isAdding = false
            addError = failure?.message
            if failure == nil {
                self.address = ""
            }
        }
    }

    private func importOPML(from url: URL) {
        let access = url.startAccessingSecurityScopedResource()
        defer {
            if access { url.stopAccessingSecurityScopedResource() }
        }
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            importReport = ImportReport(error: error.localizedDescription)
            return
        }
        isImportRunning = true
        Task {
            do {
                let result = try await model.importOPML(data)
                importReport = ImportReport(result: result)
            } catch {
                importReport = ImportReport(error: "This isn't an OPML file.")
            }
            isImportRunning = false
        }
    }

    private func export() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "Feedini.opml"
        panel.allowedContentTypes = Self.opmlTypes
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try model.exportOPML().write(to: url, options: .atomic)
        } catch {
            importReport = ImportReport(error: "Export failed: \(error.localizedDescription)")
        }
    }
}

/// Last download of a feed: when, or why it failed.
private struct FeedStatus: View {
    let feed: Feed

    var body: some View {
        if let error = feed.lastError {
            Label(error, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
                .help(error)
        } else if let checked = feed.lastChecked {
            Text(RelativeTime.updated(checked, now: .now)).foregroundStyle(.secondary)
        } else {
            Text("Not updated yet").foregroundStyle(.secondary)
        }
    }
}

private struct ImportReport: Identifiable {
    let id = UUID()
    var added = 0
    var skipped: [(title: String, address: String, reason: String)] = []
    var error: String?

    init(result: FeedSubscriber.ImportResult) {
        added = result.added.count
        skipped = result.skipped.map { ($0.entry.title, $0.entry.feedURL, $0.reason) }
    }

    init(error: String) {
        self.error = error
    }
}

private struct ImportReportView: View {
    @Environment(\.dismiss) private var dismiss
    let report: ImportReport

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let error = report.error {
                Label(error, systemImage: "exclamationmark.triangle").font(.headline)
            } else {
                Text(report.added == 1 ? "Added 1 feed." : "Added \(report.added) feeds.").font(.headline)
                if !report.skipped.isEmpty {
                    Text("Not added:")
                    List(report.skipped, id: \.address) { item in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.title).fontWeight(.medium)
                            Text(item.address).font(.caption).foregroundStyle(.secondary)
                            Text(item.reason).font(.caption).foregroundStyle(.orange)
                        }
                    }
                    .frame(minHeight: 160)
                }
            }
            HStack {
                Spacer()
                Button("OK") { dismiss() }.keyboardShortcut(.defaultAction)
            }
        }
        .padding()
        .frame(width: 460)
    }
}
