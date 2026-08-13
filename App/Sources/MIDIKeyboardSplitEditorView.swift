import SwiftUI
import AppCore
import MusicTheoryKit
import JamShackUI

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
                    SplitZonesKeyboardOverview(zones: zones)
                        .listRowInsets(EdgeInsets())
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

/// A read-only full-range (0...127) piano overview with each zone tinted a distinct color over
/// its own key range, its name above and its octave-shift transposition below — lets the user
/// see the whole split at a glance instead of piecing it together from the picker rows alone.
/// Draws `PitchKeyboardView` itself (that view already knows how to lay out 128 keys — no
/// `onNoteOn`/`onNoteOff` here, so it's non-interactive) and overlays the zone tints/labels on
/// top using the SAME white-key-slot math `PitchKeyboardView` uses internally (duplicated here
/// in miniature since that layout function isn't exported outside `JamShackUI`).
private struct SplitZonesKeyboardOverview: View {
    let zones: [MIDIKeyboardSplit.Zone]

    private static let minMidi = 0
    private static let maxMidi = 127
    private static let topLabelHeight: CGFloat = 16
    private static let bottomLabelHeight: CGFloat = 16
    private static let keysHeight: CGFloat = 90

    private static let zoneColors: [Color] = [.blue, .orange, .green, .pink, .purple, .mint, .indigo, .brown]

    // Same tables/formula as `PitchKeyboardView.absoluteWhiteSlot` — kept in sync by hand since
    // that one is `internal` to `JamShackUI`, not exported.
    private static let whiteSlotBySemitone: [Int: Int] = [0: 0, 2: 1, 4: 2, 5: 3, 7: 4, 9: 5, 11: 6]
    private static let blackAfterWhiteSlot: [Int: Int] = [1: 0, 3: 1, 6: 3, 8: 4, 10: 5]

    private static func absoluteWhiteSlot(forPitch pitch: Int) -> Double {
        let pitchClass = ((pitch % 12) + 12) % 12
        let octave = pitch / 12
        if let whiteSlot = whiteSlotBySemitone[pitchClass] {
            return Double(octave * 7 + whiteSlot)
        }
        return Double(octave * 7 + blackAfterWhiteSlot[pitchClass]!) + 0.5
    }

    private static let totalWhiteSlots = absoluteWhiteSlot(forPitch: maxMidi) - absoluteWhiteSlot(forPitch: minMidi) + 1

    /// Fraction (0...1) along the full keyboard's width where `pitch`'s key starts/ends —
    /// `edge: 1` lands on the NEXT key's own start, giving a black key's boundary the same
    /// flush-with-its-neighboring-white-keys width a zone boundary needs.
    private static func xFraction(ofPitch pitch: Int, edge: Double) -> Double {
        (absoluteWhiteSlot(forPitch: pitch) - absoluteWhiteSlot(forPitch: minMidi) + edge) / totalWhiteSlots
    }

    private func compactOctaveShiftLabel(_ octaves: Int) -> String {
        octaves == 0 ? "—" : "\(octaves > 0 ? "+" : "")\(octaves) oct"
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .topLeading) {
                PitchKeyboardView(minMidi: Self.minMidi, maxMidi: Self.maxMidi, height: Self.keysHeight)
                    .offset(y: Self.topLabelHeight)
                ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                    let x0 = CGFloat(Self.xFraction(ofPitch: zone.lowPitch, edge: 0)) * width
                    let x1 = CGFloat(Self.xFraction(ofPitch: zone.highPitch, edge: 1)) * width
                    let zoneWidth = max(1, x1 - x0)
                    let color = Self.zoneColors[index % Self.zoneColors.count]
                    Rectangle()
                        .fill(color.opacity(0.32))
                        .frame(width: zoneWidth, height: Self.keysHeight)
                        .offset(x: x0, y: Self.topLabelHeight)
                    Text(zone.name)
                        .font(.caption2)
                        .lineLimit(1)
                        .minimumScaleFactor(0.6)
                        .frame(width: zoneWidth)
                        .offset(x: x0, y: 0)
                    Text(compactOctaveShiftLabel(zone.octaveShift))
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .frame(width: zoneWidth)
                        .offset(x: x0, y: Self.topLabelHeight + Self.keysHeight)
                }
            }
        }
        .frame(height: Self.topLabelHeight + Self.keysHeight + Self.bottomLabelHeight)
    }
}
