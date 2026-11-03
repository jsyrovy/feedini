import SwiftUI

/// Restoring a backup: the backups of all Macs, the newest selected, then a confirmation with what the backup holds.
struct RestoreSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    private enum Phase {
        case listing, ready, reading, restoring
    }

    @State private var phase = Phase.listing
    @State private var backups: [BackupStore.Backup] = []
    @State private var selection: BackupStore.Backup.ID?
    @State private var restoresSettings = true
    @State private var error: String?
    /// The backup read and waiting for the confirmation.
    @State private var confirming: BackupFile.Contents?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Restore from Backup")
                .font(.title2.bold())
            Text("Replaces your library with a backup from iCloud Drive. Your current library is backed up first.")
                .foregroundStyle(.secondary)
            Table(backups, selection: $selection) {
                TableColumn("Date") { backup in
                    Text(created(backup))
                }
                TableColumn("Mac", value: \.device)
                TableColumn("Size") { backup in
                    HStack(spacing: 4) {
                        Text(backup.size.map { Int64($0).formatted(.byteCount(style: .file)) } ?? "")
                        if !backup.isDownloaded {
                            Image(systemName: "icloud.and.arrow.down")
                                .help("Only in iCloud; it is downloaded first.")
                        }
                    }
                }
                .width(90)
            }
            .overlay {
                if phase == .ready && backups.isEmpty {
                    ContentUnavailableView("No Backups", systemImage: "externaldrive.badge.icloud")
                }
            }
            Toggle("Also restore settings", isOn: $restoresSettings)
            Text(
                "Refreshing, AI and models, the summary language, where pages open. Not the path to claude or backups."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
            HStack {
                if let error {
                    Text(error).foregroundStyle(.orange)
                } else if let progress {
                    ProgressView().controlSize(.small)
                    Text(progress).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Restore…") { read() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(selected == nil || phase != .ready)
            }
        }
        .padding(20)
        .frame(width: 600, height: 420)
        .task { await list() }
        .alert(
            confirmationTitle, isPresented: $confirming.isPresent(), presenting: confirming,
            actions: { contents in
                Button("Restore", role: .destructive) { restore(contents) }
                Button("Cancel", role: .cancel) {}
            },
            message: { contents in
                Text(
                    "\(contents.summary). Your current library is backed up to iCloud Drive first. The reading history "
                        + "for ⌘Z starts over.")
            })
    }

    private var selected: BackupStore.Backup? {
        backups.first { $0.id == selection }
    }

    private var progress: String? {
        switch phase {
        case .listing: "Looking for backups…"
        case .reading: selected?.isDownloaded == false ? "Downloading the backup…" : "Reading the backup…"
        case .restoring: "Restoring…"
        case .ready: nil
        }
    }

    private var confirmationTitle: String {
        guard let selected else { return "Restore the backup?" }
        return "Replace your library with the backup from \(created(selected))?"
    }

    private func created(_ backup: BackupStore.Backup) -> String {
        let date = backup.created.formatted(date: .abbreviated, time: .shortened)
        return backup.kind == .beforeRestore ? "\(date) (before restore)" : date
    }

    private func list() async {
        do {
            backups = try await model.backups.backups()
            selection = backups.first?.id
        } catch {
            self.error = error.message
        }
        phase = .ready
    }

    private func read() {
        guard let selected else { return }
        phase = .reading
        error = nil
        Task {
            do throws(BackupError) {
                confirming = try await model.backups.contents(of: selected)
                phase = .ready
            } catch {
                self.error = error.message
                phase = .ready
            }
        }
    }

    private func restore(_ contents: BackupFile.Contents) {
        phase = .restoring
        Task {
            do throws(BackupError) {
                try await model.restore(contents, settings: restoresSettings)
                dismiss()
            } catch {
                self.error = "The current library couldn't be backed up, nothing was restored: \(error.message)"
                phase = .ready
            }
        }
    }
}
