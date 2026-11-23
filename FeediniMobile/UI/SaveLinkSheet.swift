import SwiftUI

/// Save Link: saves a web page by its address into Saved and loads its text in the background (no summary on the
/// iPhone; T on the Mac writes one).
struct SaveLinkSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @State private var address = ""
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://", text: $address)
                        .keyboardType(.URL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .onSubmit(save)
                    // Pasting with the button doesn't make iOS ask for the clipboard.
                    PasteButton(payloadType: URL.self) { urls in
                        if let url = urls.first {
                            address = url.absoluteString
                        }
                    }
                    if let message {
                        Text(message).font(.footnote).foregroundStyle(.orange)
                    }
                } footer: {
                    Text("The page's text is loaded now, so it stays readable even if the page goes away.")
                }
            }
            .navigationTitle("Save Link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save", action: save)
                        .disabled(address.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
    }

    private func save() {
        do {
            switch try model.saveLink(address) {
            case .saved: dismiss()
            case .alreadySaved: message = "This page is in Saved already."
            }
        } catch {
            message = error.message
        }
    }
}
