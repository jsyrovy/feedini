import SwiftUI

/// Sync: the library with other devices through iCloud, its state, deleting the iCloud data.
struct SyncSettings: View {
    @Environment(MacServices.self) private var mac
    @State private var isConfirmingDeletion = false
    @State private var deletionError: String?

    var body: some View {
        @Bindable var preferences = mac.preferences
        let sync = mac.sync
        Form {
            Section {
                Toggle("Sync with iCloud", isOn: $preferences.syncsWithICloud)
            } footer: {
                Text(
                    "Feeds, folders, articles with what you read and saved, page texts, stories, topics and summaries "
                        + "go to iCloud and to Feedini on your iPhone. Their content is end-to-end encrypted with "
                        + "Advanced Data Protection. Turning sync off keeps the library here and the data in iCloud."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                LabeledContent("Status:", value: status(sync.status))
                if let problem = sync.status.problem {
                    Text(problem).font(.caption).foregroundStyle(.orange)
                }
                if let deletionError {
                    Text(deletionError).font(.caption).foregroundStyle(.orange)
                }
                HStack {
                    Spacer()
                    Button("Delete iCloud Data…", role: .destructive) { isConfirmingDeletion = true }
                        .disabled(!sync.isRunning)
                }
            }
        }
        .formStyle(.grouped)
        .confirmationDialog(
            "Delete the Feedini data in iCloud?", isPresented: $isConfirmingDeletion, titleVisibility: .visible
        ) {
            Button("Delete iCloud Data", role: .destructive) {
                Task {
                    do {
                        try await sync.deleteICloudData()
                        preferences.syncsWithICloud = false
                        deletionError = nil
                    } catch {
                        deletionError = error.localizedDescription
                    }
                }
            }
        } message: {
            Text(
                "The library stays on this Mac. Sync turns off here and on your other devices; turning it on again "
                    + "uploads this library.")
        }
    }

    private func status(_ status: SyncStatus) -> String {
        switch status {
        case .off: "Off"
        case .syncing: "Syncing…"
        case .synced(let date):
            date.map { "Synced at \($0.formatted(date: .abbreviated, time: .shortened))" } ?? "On"
        case .unavailable, .failed, .needsUpdate: "Not syncing"
        }
    }
}
