import SwiftUI
import AppCore
import MusicTheoryKit
import JamShackUI
#if os(macOS)
import AppKit
#endif

/// Shared between the zone list rows (small color swatch next to the name) and the keyboard
/// overview (band tint) so a zone's color means the same thing in both places — assigned by
/// POSITION in `zones`, not by the zone's own identity, same as the "Clavier N" default name
/// numbering already is.
private let zoneColors: [Color] = [.blue, .orange, .green, .pink, .purple, .mint, .indigo, .brown]

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
                    SplitZonesKeyboardOverview(zones: $zones)
                        .listRowInsets(EdgeInsets())
                        // Forces a full remeasure of this row when the number of result bar rows
                        // could change — `Form`/`List` on macOS otherwise sometimes keeps a stale
                        // cached row height for a couple of zones added consecutively, clipping
                        // the newest row instead of growing to fit it.
                        .id(zones.count)
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
        let zoneID = zone.wrappedValue.id
        let index = zones.firstIndex(where: { $0.id == zoneID }) ?? 0
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Circle()
                    .fill(zoneColors[index % zoneColors.count])
                    .frame(width: 10, height: 10)
                TextField("Nom", text: zone.name)
            }
            HStack {
                HStack(spacing: 4) {
                    Text("De")
                    Picker("", selection: Binding(
                        get: { zone.wrappedValue.lowPitch },
                        set: { setLowPitch($0, forZoneID: zoneID) }
                    )) {
                        ForEach(0...127, id: \.self) { pitch in Text(noteLabel(forMidiPitch: pitch)).tag(pitch) }
                    }
                    .labelsHidden()
                    Text("à")
                    Picker("", selection: Binding(
                        get: { zone.wrappedValue.highPitch },
                        set: { setHighPitch($0, forZoneID: zoneID) }
                    )) {
                        ForEach(0...127, id: \.self) { pitch in Text(noteLabel(forMidiPitch: pitch)).tag(pitch) }
                    }
                    .labelsHidden()
                }
                .pickerStyle(.menu)
                Spacer()
                octaveShiftControl(zone: zone)
            }
        }
    }

    /// Left/right buttons instead of a `Stepper`'s up/down chevrons, per explicit request —
    /// same ±1 step, same `-4...4` clamp, just laid out horizontally with the current value
    /// centered between the two buttons.
    private func octaveShiftControl(zone: Binding<MIDIKeyboardSplit.Zone>) -> some View {
        HStack(spacing: 8) {
            Button {
                zone.wrappedValue.octaveShift = max(-4, zone.wrappedValue.octaveShift - 1)
            } label: {
                Image(systemName: "chevron.left")
            }
            .buttonStyle(.borderless)
            .disabled(zone.wrappedValue.octaveShift <= -4)

            Text(octaveShiftLabel(zone.wrappedValue.octaveShift))
                .frame(minWidth: 130)
                .multilineTextAlignment(.center)

            Button {
                zone.wrappedValue.octaveShift = min(4, zone.wrappedValue.octaveShift + 1)
            } label: {
                Image(systemName: "chevron.right")
            }
            .buttonStyle(.borderless)
            .disabled(zone.wrappedValue.octaveShift >= 4)
        }
    }

    /// Extending a zone's low edge DOWN into a neighbor no longer just overlaps it (forcing a
    /// manual fix via the red banner) — the neighbor directly below (the other zone whose old
    /// `highPitch` was the closest one still under this zone's old `lowPitch`) gets pushed down
    /// to stay flush and non-overlapping. Only fires when actually moving downward — shrinking
    /// a zone (raising its low edge) never touches a neighbor, since nothing is being claimed.
    private func setLowPitch(_ newValue: Int, forZoneID zoneID: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == zoneID }) else { return }
        let oldLow = zones[index].lowPitch
        zones[index].lowPitch = newValue
        guard newValue < oldLow else { return }
        if let prevIndex = zones.indices
            .filter({ $0 != index && zones[$0].highPitch < oldLow })
            .max(by: { zones[$0].highPitch < zones[$1].highPitch }),
           zones[prevIndex].highPitch >= newValue {
            zones[prevIndex].highPitch = newValue - 1
        }
    }

    /// Mirror of `setLowPitch` for extending a zone's high edge UP into the neighbor above it.
    private func setHighPitch(_ newValue: Int, forZoneID zoneID: UUID) {
        guard let index = zones.firstIndex(where: { $0.id == zoneID }) else { return }
        let oldHigh = zones[index].highPitch
        zones[index].highPitch = newValue
        guard newValue > oldHigh else { return }
        if let nextIndex = zones.indices
            .filter({ $0 != index && zones[$0].lowPitch > oldHigh })
            .min(by: { zones[$0].lowPitch < zones[$1].lowPitch }),
           zones[nextIndex].lowPitch <= newValue {
            zones[nextIndex].lowPitch = newValue + 1
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

/// A read-only full-range (0...127) piano overview: each zone's own range is tinted on the top
/// keyboard, in a band tall enough to hold the zone's name right inside it (rather than as a
/// separate caption above), with the octave-shift transposition below. A second keyboard below
/// shows where each zone actually SOUNDS once that transposition is applied — same colors, one
/// bar per zone stacked in its OWN row (never sharing a row with another zone, even when their
/// transposed ranges overlap, so every bar stays fully visible and lines up predictably with the
/// zone list above). Draws `PitchKeyboardView` itself (that view already knows how to lay out
/// 128 keys — no `onNoteOn`/`onNoteOff` here, so it's non-interactive) and overlays the zone
/// tints/labels/bars on top using the SAME white-key-slot math `PitchKeyboardView` uses
/// internally (duplicated here in miniature since that layout function isn't exported outside
/// `JamShackUI`).
private struct SplitZonesKeyboardOverview: View {
    @Binding var zones: [MIDIKeyboardSplit.Zone]

    /// The boundary's own x position, captured ONCE when a drag starts (keyed by
    /// `ZoneBoundary.id`) — using `DragGesture`'s `translation` against a reference point that's
    /// re-read from `zones` on every callback (which the drag itself just mutated) compounds:
    /// each tiny mouse move adds translation on top of an ALREADY-moved base, snapping straight
    /// to the clamp limit after a couple of updates. Freezing the base at drag-start and adding
    /// the full translation to THAT fixed point instead keeps the marker under the cursor.
    @State private var boundaryDragStartX: [Int: CGFloat] = [:]
    /// Same fix, same reason, for dragging a result band to retarget its `octaveShift`.
    @State private var resultDragStartOctaveShift: [UUID: Int] = [:]

    private static let minMidi = 0
    private static let maxMidi = 127
    /// Taller than a plain caption line — tall enough that the zone's name sits comfortably
    /// inside the colored band itself, per explicit request, instead of floating above it.
    private static let nameStripHeight: CGFloat = 22
    private static let bottomLabelHeight: CGFloat = 18
    private static let keysHeight: CGFloat = 63 // 90 * 0.7 — 30% shorter, per explicit request
    private static let sectionGap: CGFloat = 14
    private static let resultHeaderHeight: CGFloat = 16
    private static let resultBarGap: CGFloat = 4
    /// Same height as `nameStripHeight` — the result rows get the exact same "solid band with
    /// the zone's name inside" treatment as the source overview, per explicit request, just
    /// stacked one per row below the second keyboard instead of sitting above the first one.
    private static let resultBarHeight: CGFloat = nameStripHeight
    private static let resultRowGap: CGFloat = 3

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

    /// One shared edge between two zones that actually touch (zone `upperIndex`'s `lowPitch`
    /// is exactly zone `lowerIndex`'s `highPitch + 1`) — the only case with a single draggable
    /// line to show; a gap between two zones has no shared edge to grab.
    private struct ZoneBoundary: Identifiable {
        let lowerIndex: Int
        let upperIndex: Int
        var id: Int { lowerIndex }
    }

    private var boundaries: [ZoneBoundary] {
        zones.indices.compactMap { i in
            guard let j = zones.indices.first(where: { zones[$0].lowPitch == zones[i].highPitch + 1 }) else { return nil }
            return ZoneBoundary(lowerIndex: i, upperIndex: j)
        }
    }

    /// The pitch whose key is closest to an absolute x position — the inverse of `xFraction`,
    /// done by brute-force search over all 128 keys (cheap enough to run on every drag delta)
    /// rather than a closed-form inverse, since black keys sit at a fractional offset that
    /// makes a direct algebraic inversion easy to get subtly wrong.
    private func pitchAt(x: CGFloat, width: CGFloat) -> Int {
        guard width > 0 else { return Self.minMidi }
        let targetSlot = Double(x / width) * Self.totalWhiteSlots + Self.absoluteWhiteSlot(forPitch: Self.minMidi)
        var best = Self.minMidi
        var bestDistance = Double.greatestFiniteMagnitude
        for pitch in Self.minMidi...Self.maxMidi {
            let distance = abs(Self.absoluteWhiteSlot(forPitch: pitch) - targetSlot)
            if distance < bestDistance {
                bestDistance = distance
                best = pitch
            }
        }
        return best
    }

    /// Dragging a boundary moves BOTH zones sharing it together, always clamped so neither one
    /// ever shrinks past 1 note or crosses the OTHER boundary of either zone — a drag can never
    /// produce an overlap or an invalid (empty) zone, so this needs no separate validation.
    private func moveBoundary(_ boundary: ZoneBoundary, toX newX: CGFloat, width: CGFloat) {
        let newPitch = pitchAt(x: newX, width: width)
        let minBound = zones[boundary.lowerIndex].lowPitch + 1
        let maxBound = zones[boundary.upperIndex].highPitch
        let clamped = min(max(newPitch, minBound), maxBound)
        zones[boundary.lowerIndex].highPitch = clamped - 1
        zones[boundary.upperIndex].lowPitch = clamped
    }

    /// One octave's own width in points — dragging a result band by roughly this many points
    /// retargets it by one whole octave, matching the "juste un shift d'octave" design
    /// constraint (never a finer-grained drag).
    private func octaveWidth(width: CGFloat) -> CGFloat {
        CGFloat(7.0 / Self.totalWhiteSlots) * width
    }

    /// Where `zone` actually sounds after its own transposition, clipped to the valid MIDI
    /// range — mirrors `MIDIKeyboardSplit.zone(forPitch:)`'s own per-note behavior: a note that
    /// would land outside `0...127` is dropped, never wrapped or clamped, so the sounding range
    /// is the zone's own range shifted uniformly and then simply cut off at either end. `nil`
    /// when the WHOLE zone transposes out of range (nothing from it would ever sound).
    private func soundingRange(for zone: MIDIKeyboardSplit.Zone) -> ClosedRange<Int>? {
        let shift = zone.octaveShift * 12
        let low = max(0, zone.lowPitch + shift)
        let high = min(127, zone.highPitch + shift)
        guard low <= high else { return nil }
        return low...high
    }

    /// One row per zone, ALWAYS — never packed onto a shared row even when two transposed
    /// ranges don't actually overlap, per explicit request. Row index = the zone's own position
    /// in `zones`, so it's fully deterministic (adding zone N+1 only ever adds row N+1, never
    /// reshuffles earlier rows the way a greedy overlap-packing scheme could).
    private var resultRowCount: Int { zones.count }

    private var resultBarsHeight: CGFloat {
        guard resultRowCount > 0 else { return 0 }
        return CGFloat(resultRowCount) * Self.resultBarHeight + CGFloat(resultRowCount - 1) * Self.resultRowGap
    }

    /// A few extra points beyond the exact sum of every piece below — cheap insurance against
    /// off-by-a-few-points clipping at the very bottom row (some platforms round text/row
    /// metrics up slightly; better to have a sliver of empty space than a clipped bar).
    private static let bottomSafetyMargin: CGFloat = 8

    private var totalHeight: CGFloat {
        Self.nameStripHeight + Self.keysHeight + Self.bottomLabelHeight
            + Self.sectionGap + Self.resultHeaderHeight + Self.keysHeight + Self.resultBarGap + resultBarsHeight
            + Self.bottomSafetyMargin
    }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            VStack(alignment: .leading, spacing: 0) {
                // Source: which real keys belong to each virtual keyboard, name inside its own
                // band (a taller, near-solid strip above the keys, continuing as a lighter tint
                // over the keys themselves) and the transposition below.
                ZStack(alignment: .topLeading) {
                    PitchKeyboardView(minMidi: Self.minMidi, maxMidi: Self.maxMidi, height: Self.keysHeight)
                        .offset(y: Self.nameStripHeight)
                    ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                        let x0 = CGFloat(Self.xFraction(ofPitch: zone.lowPitch, edge: 0)) * width
                        let x1 = CGFloat(Self.xFraction(ofPitch: zone.highPitch, edge: 1)) * width
                        let zoneWidth = max(1, x1 - x0)
                        let color = zoneColors[index % zoneColors.count]
                        Rectangle()
                            .fill(color.opacity(0.85))
                            .frame(width: zoneWidth, height: Self.nameStripHeight)
                            .offset(x: x0, y: 0)
                        Rectangle()
                            .fill(color.opacity(0.28))
                            .frame(width: zoneWidth, height: Self.keysHeight)
                            .offset(x: x0, y: Self.nameStripHeight)
                        Text(zone.name)
                            .font(.caption2.bold())
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                            .frame(width: zoneWidth, height: Self.nameStripHeight)
                            .offset(x: x0, y: 0)
                        Text(compactOctaveShiftLabel(zone.octaveShift))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .frame(width: zoneWidth)
                            .offset(x: x0, y: Self.nameStripHeight + Self.keysHeight)
                    }
                    // Draggable boundary between two zones that actually touch — drag left/right
                    // to resize both at once instead of only via the pickers below.
                    ForEach(boundaries) { boundary in
                        let pitch = zones[boundary.upperIndex].lowPitch
                        let x = CGFloat(Self.xFraction(ofPitch: pitch, edge: 0)) * width
                        Rectangle()
                            .fill(Color.red)
                            .frame(width: 3)
                            .frame(width: 16, height: Self.nameStripHeight + Self.keysHeight)
                            .contentShape(Rectangle())
                            .offset(x: x - 8, y: 0)
                            #if os(macOS)
                            .onHover { inside in
                                if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                            }
                            #endif
                            .gesture(
                                DragGesture(minimumDistance: 1)
                                    .onChanged { value in
                                        let startX = boundaryDragStartX[boundary.id] ?? x
                                        if boundaryDragStartX[boundary.id] == nil {
                                            boundaryDragStartX[boundary.id] = x
                                        }
                                        moveBoundary(boundary, toX: startX + value.translation.width, width: width)
                                    }
                                    .onEnded { _ in
                                        boundaryDragStartX[boundary.id] = nil
                                    }
                            )
                    }
                }
                .frame(height: Self.nameStripHeight + Self.keysHeight + Self.bottomLabelHeight)

                // Result: where each virtual keyboard actually sounds once its own
                // transposition is applied — same colors as above, one row per zone always, so
                // a mismatch (a bar that doesn't line up with where you expect, or one that's
                // missing entirely because it transposed out of range) is obvious at a glance.
                VStack(alignment: .leading, spacing: 2) {
                    Text("Résultat après transposition")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .frame(height: Self.resultHeaderHeight, alignment: .center)
                    PitchKeyboardView(minMidi: Self.minMidi, maxMidi: Self.maxMidi, height: Self.keysHeight)
                    // Genuinely stacked rows (a plain VStack, one per zone) rather than
                    // absolutely-Y-offset bars inside one fixed-height ZStack — the latter hit a
                    // real SwiftUI/AppKit List-row ceiling somewhere around 3 rows' worth of
                    // offset content: extra rows kept drawing (at the right position) but the
                    // ENCLOSING frame stopped growing to fit them, clipping them out regardless
                    // of how much height was requested. Each row still needs
                    // `.padding(.leading:)` for its own HORIZONTAL position (that part scales
                    // fine), just not for vertical stacking, which a VStack already does
                    // reliably at any row count.
                    VStack(alignment: .leading, spacing: Self.resultRowGap) {
                        ForEach(Array(zones.enumerated()), id: \.element.id) { index, zone in
                            if let range = soundingRange(for: zone) {
                                let x0 = CGFloat(Self.xFraction(ofPitch: range.lowerBound, edge: 0)) * width
                                let x1 = CGFloat(Self.xFraction(ofPitch: range.upperBound, edge: 1)) * width
                                let color = zoneColors[index % zoneColors.count]
                                let barWidth = max(1, x1 - x0)
                                // The gesture lives on THIS outer row — a full-width, fixed-height
                                // container whose own frame never changes during the drag. The
                                // visual band inside moves via `.offset`, which (unlike the
                                // `.padding(.leading:)` this used before) never resizes/repositions
                                // the gesture's own view. Retargeting jumps a full octave's width
                                // at once (by design — whole-octave steps only), and doing that to
                                // the SAME view the gesture tracks was exactly what made the drag
                                // flicker/lose tracking; a stable outer row fixes it.
                                ZStack(alignment: .leading) {
                                    ZStack(alignment: .leading) {
                                        Rectangle().fill(color)
                                        Text(zone.name)
                                            .font(.caption2.bold())
                                            .foregroundStyle(.white)
                                            .lineLimit(1)
                                            .minimumScaleFactor(0.6)
                                            .frame(width: barWidth, alignment: .center)
                                    }
                                    .frame(width: barWidth, height: Self.resultBarHeight)
                                    .offset(x: x0)
                                }
                                .frame(maxWidth: .infinity, minHeight: Self.resultBarHeight, maxHeight: Self.resultBarHeight, alignment: .leading)
                                .contentShape(Rectangle())
                                #if os(macOS)
                                .onHover { inside in
                                    if inside { NSCursor.resizeLeftRight.push() } else { NSCursor.pop() }
                                }
                                #endif
                                // Drag left/right to retarget this zone's own transposition —
                                // same fixed-drag-start-value fix as the boundary markers above,
                                // snapped to whole octaves per `octaveWidth(width:)`.
                                .gesture(
                                    DragGesture(minimumDistance: 2)
                                        .onChanged { value in
                                            let startShift = resultDragStartOctaveShift[zone.id] ?? zone.octaveShift
                                            if resultDragStartOctaveShift[zone.id] == nil {
                                                resultDragStartOctaveShift[zone.id] = zone.octaveShift
                                            }
                                            let octaveDelta = Int((value.translation.width / octaveWidth(width: width)).rounded())
                                            let newShift = min(4, max(-4, startShift + octaveDelta))
                                            if let zoneIndex = zones.firstIndex(where: { $0.id == zone.id }) {
                                                zones[zoneIndex].octaveShift = newShift
                                            }
                                        }
                                        .onEnded { _ in
                                            resultDragStartOctaveShift[zone.id] = nil
                                        }
                                )
                            }
                        }
                    }
                    .padding(.top, Self.resultBarGap)
                }
                .padding(.top, Self.sectionGap)
            }
        }
        .frame(height: totalHeight)
    }
}
