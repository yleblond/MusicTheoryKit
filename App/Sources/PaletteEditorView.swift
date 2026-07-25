import SwiftUI
import AppCore
import MusicTheoryKit

/// A popup editor for one color palette: a name field and a `ColorPicker` per pitch class —
/// used both to edit an existing palette (`existingIndex` set) and to create a brand-new one
/// (`existingIndex` nil, starting from `ColorPalette.builtInDefaults[0]`'s colors as a real
/// starting point to tweak, not 12 copies of one color).
struct PaletteEditorView: View {
    let session: ImprovSession
    let existingIndex: Int?

    @State private var name: String
    @State private var colors: [String]
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    private static let noteNames = ["Do", "Do#", "Re", "Re#", "Mi", "Fa", "Fa#", "Sol", "Sol#", "La", "La#", "Si"]

    init(session: ImprovSession, existingIndex: Int?) {
        self.session = session
        self.existingIndex = existingIndex
        if let existingIndex, session.colorPalettes.indices.contains(existingIndex) {
            let palette = session.colorPalettes[existingIndex]
            _name = State(initialValue: palette.name)
            _colors = State(initialValue: palette.colors)
        } else {
            _name = State(initialValue: "Nouvelle palette")
            _colors = State(initialValue: ColorPalette.builtInDefaults[0].colors)
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                if let error {
                    Section { Text(error).foregroundStyle(.red).font(.caption) }
                }
                Section {
                    TextField("Nom", text: $name)
                } header: {
                    Text("Nom de la palette")
                }
                Section {
                    ForEach(0..<12, id: \.self) { index in
                        HStack {
                            Text(Self.noteNames[index])
                            Spacer()
                            ColorPicker("", selection: Binding(
                                get: { Color(hex: colors[index]) },
                                set: { colors[index] = $0.hexString }
                            ))
                            .labelsHidden()
                        }
                    }
                } header: {
                    Text("Couleurs (une par note)")
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(existingIndex == nil ? "Nouvelle palette" : "Modifier la palette")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 380, minHeight: 480)
        #endif
    }

    private func save() {
        do {
            if let existingIndex {
                try session.renameColorPalette(atIndex: existingIndex, name: name)
                try session.updateColorPalette(atIndex: existingIndex, colors: colors)
            } else {
                try session.addColorPalette(name: name, colors: colors)
            }
            dismiss()
        } catch {
            self.error = "\(error)"
        }
    }
}

#Preview {
    PaletteEditorView(session: ImprovSession(), existingIndex: nil)
}
