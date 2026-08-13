import SwiftUI
import AppCore
import MusicTheoryKit

/// Edits one real MIDI device's split configuration (see `MIDIKeyboardSplit`) — presented as a
/// sheet from `JamShackMIDIView`'s own per-source row, same `.sheet(item:)` convention
/// `JamShackColorsView`'s `PaletteEditorView` already uses.
struct MIDIKeyboardSplitEditorView: View {
    let session: ImprovSession
    let uniqueID: Int32?
    let displayName: String

    @Environment(\.dismiss) private var dismiss
    @State private var isEnabled: Bool
    @State private var zones: [MIDIKeyboardSplit.Zone]
    @State private var saveError: String?

    init(session: ImprovSession, uniqueID: Int32?, displayName: String) {
        self.session = session
        self.uniqueID = uniqueID
        self.displayName = displayName
        let existing = session.midiKeyboardSplit(uniqueID: uniqueID, displayName: displayName)
        _isEnabled = State(initialValue: existing?.isEnabled ?? false)
        _zones = State(initialValue: existing?.zones ?? [])
    }

    private var hasOverlap: Bool { MIDIKeyboardSplit.hasOverlap(in: zones) }
    private var hasInvalidRange: Bool { zones.contains { $0.lowPitch > $0.highPitch } }
    private var canSave: Bool { !hasOverlap && !hasInvalidRange }
    private var isRangeFullyClaimed: Bool { (zones.map(\.highPitch).max() ?? -1) >= 127 }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Activer le split pour ce clavier", isOn: $isEnabled)
                } footer: {
                    // Per explicit design decision: a split, once active, REPLACES the real
                    // keyboard entirely as a selectable source — this isn't an additional
                    // option alongside it.
                    Text("Une fois activé, ce clavier n'apparaît plus lui-même comme source — seuls les claviers virtuels ci-dessous le remplacent.")
                }
                Section {
                    ForEach($zones) { $zone in
                        zoneRow(zone: $zone)
                    }
                    .onDelete { zones.remove(atOffsets: $0) }
                    Button("Ajouter un clavier virtuel") { addZone() }
                        .disabled(isRangeFullyClaimed)
                } header: {
                    Text("Claviers virtuels")
                } footer: {
                    if hasOverlap {
                        Text("Les zones ne doivent pas se chevaucher.").foregroundStyle(.red)
                    } else if hasInvalidRange {
                        Text("La note de fin doit être après la note de début.").foregroundStyle(.red)
                    } else if isRangeFullyClaimed {
                        Text("Toute la plage du clavier est déjà répartie — réduisez une zone existante pour en ajouter une autre.")
                    } else {
                        Text("Chaque clavier virtuel a son propre nom, sa plage de notes et sa transposition.")
                    }
                }
                if let saveError {
                    Text(saveError).foregroundStyle(.red).font(.caption)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle(displayName)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Enregistrer") { save() }
                        .disabled(!canSave)
                }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private func zoneRow(zone: Binding<MIDIKeyboardSplit.Zone>) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            TextField("Nom", text: zone.name)
            HStack(spacing: 12) {
                Picker("De", selection: zone.lowPitch) {
                    ForEach(0...127, id: \.self) { pitch in Text(noteLabel(forMidiPitch: pitch)).tag(pitch) }
                }
                Picker("À", selection: zone.highPitch) {
                    ForEach(0...127, id: \.self) { pitch in Text(noteLabel(forMidiPitch: pitch)).tag(pitch) }
                }
            }
            .pickerStyle(.menu)
            Stepper(octaveShiftLabel(zone.wrappedValue.octaveShift), value: zone.octaveShift, in: -4...4)
        }
    }

    private func octaveShiftLabel(_ octaves: Int) -> String {
        octaves == 0 ? "Pas de transposition" : "Octave : \(octaves > 0 ? "+" : "")\(octaves)"
    }

    private func noteLabel(forMidiPitch midi: Int) -> String {
        let pc = ((midi % 12) + 12) % 12
        let octave = midi / 12 - 1
        return "\(session.notationStyle.rootName(PitchClass(pc), preferFlats: false))\(octave)"
    }

    /// The very first zone defaults to the LOWER half of the keyboard rather than the whole
    /// range — claiming everything up front would leave no room for a second "Ajouter" tap
    /// without first shrinking zone 1 by hand. Every zone after that still extends up to the
    /// top (127), which is what actually makes sense once there's a preceding zone below it.
    private func addZone() {
        guard !isRangeFullyClaimed else { return }
        let nextLow = (zones.map(\.highPitch).max() ?? -1) + 1
        let highPitch = zones.isEmpty ? 63 : 127
        zones.append(MIDIKeyboardSplit.Zone(
            name: "Clavier \(zones.count + 1)",
            lowPitch: min(nextLow, 127), highPitch: highPitch, octaveShift: 0
        ))
    }

    private func save() {
        guard canSave else { return }
        do {
            try session.setMIDIKeyboardSplit(uniqueID: uniqueID, displayName: displayName, split: MIDIKeyboardSplit(isEnabled: isEnabled, zones: zones))
            dismiss()
        } catch {
            saveError = "\(error)"
        }
    }
}
