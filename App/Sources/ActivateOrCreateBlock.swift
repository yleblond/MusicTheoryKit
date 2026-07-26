import SwiftUI
import Localization

/// A small reusable block for "nothing active yet" placeholders (Scene's Disposition sub-tab,
/// Guide's Edition/Lecture sub-tabs): a picklist over the relevant folder's own files (already
/// listed via JamShack > Dossiers) to activate one directly, plus a button to create a brand
/// new one — so getting started doesn't require switching to the Fichier sub-tab first.
struct ActivateOrCreateBlock: View {
    let files: [String]
    let onActivate: (String) throws -> Void
    let createButtonLabel: String
    let createAlertTitle: String
    let createFieldPlaceholder: String
    let onCreate: (String) -> Void
    let language: AppLanguage

    @State private var selection: String?
    @State private var showCreateAlert = false
    @State private var newTitle = ""
    @State private var error: String?

    var body: some View {
        VStack(spacing: 8) {
            if let error {
                Text(error).font(.caption).foregroundStyle(.red)
            }
            if !files.isEmpty {
                HStack {
                    Text(L10n.string(.optionActiver, language))
                    Picker("", selection: $selection) {
                        Text(L10n.string(.appChoisirEllipsis, language)).tag(String?.none)
                        ForEach(files, id: \.self) { name in
                            Text(name.strippingJSONExtension).tag(String?.some(name))
                        }
                    }
                    .labelsHidden()
                    .onChange(of: selection) { _, newValue in
                        guard let newValue else { return }
                        do {
                            try onActivate(newValue)
                        } catch {
                            self.error = "\(error)"
                        }
                        selection = nil
                    }
                }
            }
            Button(createButtonLabel) { showCreateAlert = true }
        }
        .alert(createAlertTitle, isPresented: $showCreateAlert) {
            TextField(createFieldPlaceholder, text: $newTitle)
            Button(L10n.string(.appCreer, language)) {
                onCreate(newTitle.isEmpty ? createFieldPlaceholder : newTitle)
                newTitle = ""
            }
            Button(L10n.string(.appAnnuler, language), role: .cancel) {}
        }
    }
}
