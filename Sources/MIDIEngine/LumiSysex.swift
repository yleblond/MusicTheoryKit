/// Encodes the proprietary SysEx messages ROLI Dashboard uses to drive a LUMI Keys'
/// per-key RGB backlight — unofficial and reverse-engineered (no ROLI documentation exists),
/// but every byte sequence here was cross-checked bit-for-bit against known-good captures
/// (see `github.com/benob/LUMI-lights`'s `SYSEX.txt`, itself captured with a MIDI monitor
/// while ROLI Dashboard was driving a real LUMI) by re-running that project's own
/// `lumi_sysex.js` under Node and diffing its output against `SYSEX.txt`'s documented
/// examples — not hand-derived from a written spec. Pure byte-array-in/byte-array-out: no
/// CoreMIDI dependency, so it's testable without any hardware or transport (see
/// `MIDIOutputPort` for the transport half).
///
/// Important protocol finding: despite `lumi_sysex.js`'s `set_color(id, r, g, b)` looking
/// like it takes a per-key index, `id` is only ever tested for its low bit (`id & 1`) to
/// choose between two *fixed* targets — "all (non-root) keys" and "the root/tonic key" —
/// exactly matching `SYSEX.txt`'s own two separate commands ("change color 1 (global key
/// color)" / "change color 2 (root key color)"). There is no true arbitrary per-key (of 24)
/// addressing in this reverse-engineered protocol: `ColorTarget` reflects that directly
/// rather than exposing a misleading `index: Int`.
public enum LumiSysex {
    public enum ColorTarget {
        /// Every key except the root — `SYSEX.txt`'s "change color 1 (global key color)".
        case allKeys
        /// The root/tonic key only — `SYSEX.txt`'s "change color 2 (root key color)".
        case root
    }

    /// The current Dashboard's five lighting-behavior presets — captured live with MIDI
    /// Monitor against a real LUMI Keys BLOCK (2026-07-20), not from `SYSEX.txt`: that file's
    /// documented four-mode table (rainbow/single-color-scale/piano/night, built from a
    /// 5-bit-tag + 2-bit-value bit-packed field) does **not** match this hardware/firmware at
    /// all — e.g. its "rainbow" bytes (`10 40 02 00...`) never appeared, while the real
    /// capture for Dashboard's own "Rainbow" menu entry was `10 40 0C 01...`. Comparing all
    /// five real captures shows the byte-3 selector value is exactly `12 + modeIndex * 32`
    /// (Pro=0, User=1, Piano=2, Stage=3, Rainbow=4) — a 5-bit tag of `0b01100` (12) plus what
    /// must be at least a 3-bit mode index, not `SYSEX.txt`'s assumed 2-bit one. Rather than
    /// rebuild that wider bit-packed field (untested for values 5+, and this product only
    /// exposes these five anyway), each mode's full 8-byte payload is reproduced literally,
    /// the same way `setScale` reproduces `SYSEX.txt`'s fixed scale tables — every checksum
    /// below was independently re-verified against this file's own `checksum(_:)`, not just
    /// copied from the capture.
    ///
    /// What each preset actually does to `setColor`'s two color registers (which one, if any,
    /// uses them; whether any animate) is unconfirmed — that's the open question motivating
    /// this enum's existence, not something already answered by having its bytes.
    public enum ColorMode {
        case user
        case pro
        case stage
        case piano
        case rainbow

        fileprivate var payload: [UInt8] {
            switch self {
            case .user: return [0x10, 0x40, 0x2C, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .pro: return [0x10, 0x40, 0x0C, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .stage: return [0x10, 0x40, 0x6C, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .piano: return [0x10, 0x40, 0x4C, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .rainbow: return [0x10, 0x40, 0x0C, 0x01, 0x00, 0x00, 0x00, 0x00]
            }
        }
    }

    /// `10 20/30 <5-bit tag> <8 bits blue><8 bits green><8 bits red><8 bits 0xFF>`,
    /// bit-packed and padded per `envelope(payload:)`. Channel order (blue, then green,
    /// then red) and the trailing `0xFF` byte are exactly what `lumi_sysex.js.set_color`
    /// sends — confirmed against `SYSEX.txt`'s six named-color examples (red/green/blue/
    /// yellow/magenta/cyan), all of which round-trip byte-for-byte through this encoding.
    public static func setColor(_ target: ColorTarget, red: UInt8, green: UInt8, blue: UInt8) -> [UInt8] {
        var bits = BitPacker()
        bits.append(0x10, size: 7)
        bits.append(target == .allKeys ? 0x20 : 0x30, size: 7)
        bits.append(0b00100, size: 5)
        bits.append(Int(blue), size: 8)
        bits.append(Int(green), size: 8)
        bits.append(Int(red), size: 8)
        bits.append(0b1111_1111, size: 8)
        return envelope(payload: bits.paddedValues())
    }

    /// `percentage` is a plain 0...100 value — confirmed directly against `SYSEX.txt`'s
    /// 0/25/50/75/100% examples, all of which round-trip byte-for-byte (earlier readings of
    /// the raw byte table suggested a 0...25-step encoding instead; that was wrong — the
    /// value really is the percentage itself, not a step count).
    public static func setBrightness(_ percentage: Int) -> [UInt8] {
        precondition((0...100).contains(percentage), "LUMI brightness is a 0...100 percentage")
        var bits = BitPacker()
        bits.append(0x10, size: 7)
        bits.append(0x40, size: 7)
        bits.append(0b00100, size: 5)
        bits.append(percentage, size: 7)
        return envelope(payload: bits.paddedValues())
    }

    public static func setColorMode(_ mode: ColorMode) -> [UInt8] {
        envelope(payload: mode.payload)
    }

    /// LUMI's fixed built-in scale list (used, in `.user` `ColorMode`, to decide which
    /// physical keys count as "in scale" and so receive `setColor(.allKeys, ...)` — the two
    /// flat colors alone don't carry that distinction). Payloads are `SYSEX.txt`'s literal
    /// scale table verbatim (not built via the bit packer, matching how `lumi_sysex.js`'s own
    /// `set_scale(name)` sends each entry as a hardcoded 8-byte array) — `.blues` and
    /// `.lydian` were independently confirmed byte-for-byte via a live Dashboard capture
    /// (2026-07-20); the rest are trusted on that same table's strength, not separately
    /// re-verified. `SYSEX.txt`'s "arabic (a)" entry is deliberately omitted: its documented
    /// bytes (`10 60 22 02...`) are byte-for-byte identical to `.lydian`'s, in both `SYSEX.txt`
    /// and `lumi_sysex.js` — almost certainly a copy-paste error in the original reverse
    /// engineering rather than a real duplicate, so it's excluded rather than risk sending
    /// the wrong scale under that name.
    ///
    /// This is a much smaller vocabulary than `MusicTheoryKit.ScaleLibrary`'s 33 scales —
    /// see `LumiColorMap` (`AppCore`) for the app-scale → `Scale` fallback mapping this
    /// implies (most of `ScaleLibrary`'s modes have no native equivalent here).
    public enum Scale {
        case major, minor, harmonicMinor, chromatic
        case pentatonicNeutral, pentatonicMajor, pentatonicMinor
        case blues, dorian, phrygian, lydian, mixolydian, locrian
        case wholeTone, arabicB, japanese, ryukyu, eightToneSpanish

        fileprivate var payload: [UInt8] {
            switch self {
            case .major: return [0x10, 0x60, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .minor: return [0x10, 0x60, 0x22, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .harmonicMinor: return [0x10, 0x60, 0x42, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .chromatic: return [0x10, 0x60, 0x42, 0x04, 0x00, 0x00, 0x00, 0x00]
            case .pentatonicNeutral: return [0x10, 0x60, 0x62, 0x00, 0x00, 0x00, 0x00, 0x00]
            case .pentatonicMajor: return [0x10, 0x60, 0x02, 0x01, 0x00, 0x00, 0x00, 0x00]
            case .pentatonicMinor: return [0x10, 0x60, 0x22, 0x01, 0x00, 0x00, 0x00, 0x00]
            case .blues: return [0x10, 0x60, 0x42, 0x01, 0x00, 0x00, 0x00, 0x00]
            case .dorian: return [0x10, 0x60, 0x62, 0x01, 0x00, 0x00, 0x00, 0x00]
            case .phrygian: return [0x10, 0x60, 0x02, 0x02, 0x00, 0x00, 0x00, 0x00]
            case .lydian: return [0x10, 0x60, 0x22, 0x02, 0x00, 0x00, 0x00, 0x00]
            case .mixolydian: return [0x10, 0x60, 0x42, 0x02, 0x00, 0x00, 0x00, 0x00]
            case .locrian: return [0x10, 0x60, 0x62, 0x02, 0x00, 0x00, 0x00, 0x00]
            case .wholeTone: return [0x10, 0x60, 0x02, 0x03, 0x00, 0x00, 0x00, 0x00]
            case .arabicB: return [0x10, 0x60, 0x42, 0x03, 0x00, 0x00, 0x00, 0x00]
            case .japanese: return [0x10, 0x60, 0x62, 0x03, 0x00, 0x00, 0x00, 0x00]
            case .ryukyu: return [0x10, 0x60, 0x02, 0x04, 0x00, 0x00, 0x00, 0x00]
            case .eightToneSpanish: return [0x10, 0x60, 0x22, 0x04, 0x00, 0x00, 0x00, 0x00]
            }
        }
    }

    public static func setScale(_ scale: Scale) -> [UInt8] {
        envelope(payload: scale.payload)
    }

    /// Sets which of the 12 chromatic pitch classes (0 = C ... 11 = B) the LUMI treats as
    /// the root/tonic — combined with `setScale`, this is what lets the firmware work out
    /// which physical keys are "in scale" (see `Scale`'s doc comment). Unlike `setScale`,
    /// this one IS built through the bit packer rather than a literal table: comparing a
    /// live Dashboard capture across 8 of the 12 notes (C, C#, D, D#, A, A#, B) showed a
    /// clean `tag(5 bits)=0b00011` + `pitchClass(4 bits)` pattern — appending those two
    /// fields through this file's own `BitPacker` reproduces all 8 captured examples
    /// byte-for-byte (2026-07-20), which is strong enough evidence to trust the packer for
    /// the 4 unconfirmed notes (E, F, F#, G, G#) too, rather than leaving them unimplemented
    /// or guessing a literal table for them.
    public static func setKey(pitchClass: Int) -> [UInt8] {
        precondition((0...11).contains(pitchClass), "pitchClass is 0 (C) ... 11 (B)")
        var bits = BitPacker()
        bits.append(0x10, size: 7)
        bits.append(0x30, size: 7)
        bits.append(0b00011, size: 5)
        bits.append(pitchClass, size: 4)
        return envelope(payload: bits.paddedValues())
    }

    /// `size` bytes, initial accumulator seeded with `payload.count` — ported verbatim from
    /// `lumi_sysex.js`'s `checksum()`. Computed over the *un-prefixed* 8-byte command
    /// payload, matching `send_sysex()`'s call order (`checksum(values)` before `0x77, 0x37`
    /// get prepended), not over the full on-the-wire command.
    static func checksum(_ payload: [UInt8]) -> UInt8 {
        var sum = payload.count
        for byte in payload {
            sum = (sum * 3 + Int(byte)) & 0xff
        }
        return UInt8(sum & 0x7f)
    }

    /// Wraps a command payload as `F0 00 21 10 77 <deviceID> <payload> <checksum> F7` —
    /// `00 21 10` is ROLI's registered manufacturer ID, `F0`/`F7` are the standard SysEx
    /// start/end bytes.
    ///
    /// `deviceID` is `0x34`, not the `0x37` `SYSEX.txt`/`lumi_sysex.js` document — confirmed
    /// by capturing ROLI Dashboard's actual traffic to a real LUMI Keys BLOCK with MIDI
    /// Monitor (2026-07-20): every command Dashboard sent used `77 34`, and the payload +
    /// checksum bytes for a matching brightness/mode change were byte-for-byte identical to
    /// what this encoder already produced, confirming the checksum/bit-packing logic was
    /// right all along and `0x37` was simply the wrong constant (whether because the old
    /// repo's unit had a different assigned ID, or ROLI changed something since). Whether
    /// `0x34` is a fixed constant for this product or a topology-assigned ID that could
    /// change on a future reconnect is unconfirmed — if commands stop working again after
    /// unplugging/replugging the LUMI, recapture with MIDI Monitor and check this byte first.
    static func envelope(payload: [UInt8], deviceID: UInt8 = 0x34) -> [UInt8] {
        [0xF0, 0x00, 0x21, 0x10, 0x77, deviceID] + payload + [checksum(payload), 0xF7]
    }
}

/// LSB-first bit packer producing MIDI-safe 7-bit bytes (each 0...127) from fields of
/// arbitrary bit width — a direct port of `lumi_sysex.js`'s `BitArray`. Kept private to this
/// file: it's an implementation detail of the LUMI wire format, not a general-purpose type.
private struct BitPacker {
    private var values: [UInt8] = []
    private var numBits = 0

    /// Appends the low `size` bits of `value`, continuing to fill whatever 7-bit byte the
    /// previous `append` left partially used rather than always starting a fresh byte —
    /// exactly `BitArray.append`'s own logic (pop the last byte back off if it's partial,
    /// OR in as many new bits as fit, push, repeat with the remainder).
    mutating func append(_ value: Int, size: Int) {
        var value = value
        var size = size
        var usedBits = numBits % 7
        var packed = 0
        if usedBits > 0 {
            packed = Int(values.removeLast())
        }
        numBits += size
        while size > 0 {
            packed |= (value << usedBits) & 127
            size -= (7 - usedBits)
            value >>= (7 - usedBits)
            values.append(UInt8(packed))
            packed = 0
            usedBits = 0
        }
    }

    /// `BitArray.get()`'s own padding: every LUMI command observed in `SYSEX.txt` is 8
    /// bytes, so short of a future command needing more, padding up to 8 with zero bytes
    /// (never truncating — a field that already overflowed 8 bytes stays as-is) matches it.
    func paddedValues() -> [UInt8] {
        values.count < 8 ? values + Array(repeating: 0, count: 8 - values.count) : values
    }
}
