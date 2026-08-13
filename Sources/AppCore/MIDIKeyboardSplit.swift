import Foundation
import SwiftData

/// One split of a real MIDI keyboard into several virtual ones, each covering its own pitch
/// range of the real keyboard and shifted by whole octaves — see
/// `ImprovSession.midiKeyboardSplit`/`setMIDIKeyboardSplit` for how instances of this connect to
/// `TrackID.midiSplitZone`. Deliberately a plain value type (not itself a `@Model`) — same split
/// as `Scene`/`Piece`/every other "parent owns a small ordered list of child structs" case in
/// this codebase (no `@Relationship` anywhere): the value type is what the rest of the app
/// actually works with, `MIDIKeyboardSplitRecord` below exists purely to get one JSON-encoded,
/// CloudKit-syncable row per device.
public struct MIDIKeyboardSplit: Codable, Equatable, Sendable {
    /// One virtual keyboard: a pitch range of the real keyboard, transposed by whole octaves.
    public struct Zone: Identifiable, Codable, Equatable, Sendable {
        public var id: UUID
        public var name: String
        /// Inclusive, `0...127`, `lowPitch <= highPitch` — the real keyboard's own pitch range
        /// this zone claims. Validated non-overlapping against every other zone in the same
        /// split by the editor UI before saving (`MIDIKeyboardSplit.hasOverlap`); `zone(forPitch:)`
        /// is defensive about it too regardless (first match wins).
        public var lowPitch: Int
        public var highPitch: Int
        /// WHOLE octaves only (±N), never raw semitones — deliberately coarser than a generic
        /// transposition control, per explicit request ("juste un shift d'octave, pas plus
        /// détaillé"). Multiplied by 12 wherever it's actually applied to a pitch.
        public var octaveShift: Int

        public init(id: UUID = UUID(), name: String, lowPitch: Int, highPitch: Int, octaveShift: Int) {
            self.id = id
            self.name = name
            self.lowPitch = lowPitch
            self.highPitch = highPitch
            self.octaveShift = octaveShift
        }
    }

    public var isEnabled: Bool
    public var zones: [Zone]

    public init(isEnabled: Bool = true, zones: [Zone] = []) {
        self.isEnabled = isEnabled
        self.zones = zones
    }

    /// The zone (if any) claiming `pitch`, plus that pitch shifted by its own `octaveShift` —
    /// `nil` either when no zone's range contains `pitch` (a gap between zones — dropped, not
    /// routed anywhere, an accepted consequence of the "no overlap" design, not an error) or
    /// when the transposed result falls outside the valid MIDI pitch range `0...127` (dropped
    /// rather than clamped — a clamped pitch would be a different, wrong note, not the one
    /// actually played).
    public func zone(forPitch pitch: Int) -> (zone: Zone, transposedPitch: Int)? {
        guard isEnabled else { return nil }
        guard let match = zones.first(where: { pitch >= $0.lowPitch && pitch <= $0.highPitch }) else { return nil }
        let transposed = pitch + match.octaveShift * 12
        guard (0...127).contains(transposed) else { return nil }
        return (match, transposed)
    }

    /// Whether any two zones in `zones` genuinely overlap — zones that merely touch at a
    /// boundary (one's `highPitch` immediately followed by the next's `lowPitch`) do NOT count.
    /// Used by the split editor UI to reject a configuration before saving.
    public static func hasOverlap(in zones: [Zone]) -> Bool {
        for i in zones.indices {
            for j in zones.indices where j > i {
                let a = zones[i], b = zones[j]
                if a.lowPitch <= b.highPitch && b.lowPitch <= a.highPitch { return true }
            }
        }
        return false
    }
}

/// Persisted per real MIDI device, matched the exact same best-effort way `MIDIDeviceIconRecord`
/// already does (`midiUniqueID` when the device reports one, else `displayName`) — see
/// `ImprovSession.midiKeyboardSplit`/`setMIDIKeyboardSplit`.
@Model
final class MIDIKeyboardSplitRecord {
    var midiUniqueID: Int32?
    var displayName: String = ""
    var encodedSplit: Data = Data()

    init(midiUniqueID: Int32?, displayName: String, split: MIDIKeyboardSplit) {
        self.midiUniqueID = midiUniqueID
        self.displayName = displayName
        self.encodedSplit = (try? JSONEncoder().encode(split)) ?? Data()
    }

    var asSplit: MIDIKeyboardSplit? {
        try? JSONDecoder().decode(MIDIKeyboardSplit.self, from: encodedSplit)
    }
}
