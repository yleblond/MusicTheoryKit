import CoreMIDI
import Foundation
import MIDIEngine

// Disposable hardware-validation CLI for the ROLI LUMI Keys' reverse-engineered LED SysEx
// protocol. Talks to real CoreMIDI destinations directly via MIDIEngine's MIDIOutputPort/
// LumiSysex — nothing here touches AppCore/ImprovSession, so poking at real hardware (and
// discovering, e.g., that a handshake is needed, or that the LUMI doesn't respond at all)
// never risks the real app's state. See /Users/amarok/.claude/plans/toasty-growing-melody.md
// (Phase 0) for the checklist this exists to work through.

func printUsageAndExit() -> Never {
    print("""
    Usage:
      LumiSpike list
      LumiSpike color <r> <g> <b> [--dest N] [--target allkeys|root]
      LumiSpike brightness <0-100> [--dest N]
      LumiSpike mode <user|pro|stage|piano|rainbow> [--dest N]
      LumiSpike scale <name> [--dest N]   e.g. major, minor, blues, dorian, mixolydian...
      LumiSpike key <note> [--dest N]     note name, e.g. C, C#, D, D#, E, F, F#, G, G#, A, A#, B
      LumiSpike reset [--dest N]    sends the "list blocks?/reset?" priming message
                                    documented in SYSEX.txt — try this if color/brightness/
                                    mode send successfully but nothing visibly happens
      LumiSpike serial [--dest N]   sends query_serial() — no reply is read back (LumiSpike
                                    has no MIDI input yet), this only confirms the send itself
      LumiSpike raw <hex bytes...> [--dest N]

    <r>/<g>/<b> are 0-255. Omit --dest to auto-pick the first destination whose name
    contains "LUMI" (case-insensitive); if none or several match, --dest is required —
    run `list` first to see indices.
    """)
    exit(1)
}

/// The exact literal SysEx bytes `lumi_sysex.js`'s `send_reset()` sends — unlike every
/// other command here, this one is hardcoded in the reference implementation rather than
/// built through `checksum`/the bit packer, so it's reproduced verbatim rather than run
/// through `LumiSysex`. SYSEX.txt describes it only as "list blocks? reset?" and notes it
/// unlocks a later "read configuration" command — worth trying first if color/brightness/
/// mode all report a successful send but the LUMI shows no reaction, in case it needs this
/// as a priming step before it'll act on device-id 0x34 (LUMI-addressed) config messages.
/// (In practice this turned out unnecessary — the real fix was the device-id byte itself,
/// see LumiSysex.envelope's doc comment — but this remains a reasonable thing to retry if
/// a future firmware/reconnect makes commands go silent again.)
let lumiResetBytes: [UInt8] = [0xF0, 0x00, 0x21, 0x10, 0x77, 0x00, 0x01, 0x01, 0x00, 0x5D, 0xF7]

/// `lumi_sysex.js`'s `query_serial()`, verbatim — SYSEX.txt documents it as returning a
/// 224-byte reply starting `F0 00 21 10 77 78...`, which LumiSpike can't read yet (no MIDI
/// input side), but sending it is still useful to try alongside `reset`.
let lumiQuerySerialBytes: [UInt8] = [0xF0, 0x00, 0x21, 0x10, 0x78, 0x3F, 0xF7]

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func resolveDestinationIndex(explicit: Int?) -> Int {
    let descriptors = MIDIOutputPort.destinationDescriptors()
    if descriptors.isEmpty {
        print("No CoreMIDI destinations found at all.")
        exit(1)
    }
    if let explicit {
        guard descriptors.indices.contains(explicit) else {
            print("--dest \(explicit) is out of range (0..<\(descriptors.count)). Run `list` first.")
            exit(1)
        }
        return explicit
    }
    guard let index = MIDIOutputPort.autoDetectedDestinationIndex(nameContains: "lumi") else {
        print("Could not auto-pick a destination (need exactly one name containing \"LUMI\"). Pass --dest explicitly:")
        for (index, descriptor) in descriptors.enumerated() {
            print("  [\(index)] \(descriptor.displayName) (uniqueID: \(descriptor.uniqueID.map(String.init) ?? "none"))")
        }
        exit(1)
    }
    return index
}

func send(_ bytes: [UInt8], destIndex: Int?) {
    let index = resolveDestinationIndex(explicit: destIndex)
    let descriptor = MIDIOutputPort.destinationDescriptors()[index]
    print("-> [\(index)] \(descriptor.displayName): \(hex(bytes))")
    do {
        let output = try MIDIOutputPort()
        try output.send(bytes, toDestinationAtIndex: index)
        print("sent (\(bytes.count) bytes)")
    } catch {
        print("send failed: \(error)")
        exit(1)
    }
}

/// Pulls every `--name value` pair in `names` out of `args`, returning the remaining
/// positional args alongside whatever was found. Every recognized flag (not just `--dest`)
/// must be stripped here, before any `positional.count == N` check downstream — `color`'s
/// `--target` previously wasn't, so `color 0 255 0 --target root` failed positional-count
/// validation and fell through to the usage message instead of being parsed.
func extractFlags(_ args: [String], names: Set<String>) -> (positional: [String], flags: [String: String]) {
    var positional: [String] = []
    var flags: [String: String] = [:]
    var i = 0
    while i < args.count {
        if names.contains(args[i]), i + 1 < args.count {
            flags[args[i]] = args[i + 1]
            i += 2
        } else {
            positional.append(args[i])
            i += 1
        }
    }
    return (positional, flags)
}

let allArgs = Array(CommandLine.arguments.dropFirst())
guard let command = allArgs.first else { printUsageAndExit() }
let (positional, flags) = extractFlags(Array(allArgs.dropFirst()), names: ["--dest", "--target"])
let destFlag = flags["--dest"].flatMap(Int.init)

switch command {
case "list":
    let descriptors = MIDIOutputPort.destinationDescriptors()
    if descriptors.isEmpty {
        print("No CoreMIDI destinations found.")
    }
    for (index, descriptor) in descriptors.enumerated() {
        print("[\(index)] \(descriptor.displayName) (uniqueID: \(descriptor.uniqueID.map(String.init) ?? "none"))")
    }

case "color":
    guard positional.count == 3,
          let r = UInt8(positional[0]), let g = UInt8(positional[1]), let b = UInt8(positional[2])
    else { printUsageAndExit() }
    var target = LumiSysex.ColorTarget.allKeys
    if let targetFlag = flags["--target"] {
        switch targetFlag {
        case "root": target = .root
        case "allkeys": target = .allKeys
        default:
            print("--target must be \"allkeys\" or \"root\"")
            exit(1)
        }
    }
    send(LumiSysex.setColor(target, red: r, green: g, blue: b), destIndex: destFlag)

case "brightness":
    guard positional.count == 1, let percentage = Int(positional[0]), (0...100).contains(percentage) else { printUsageAndExit() }
    send(LumiSysex.setBrightness(percentage), destIndex: destFlag)

case "mode":
    guard positional.count == 1 else { printUsageAndExit() }
    let mode: LumiSysex.ColorMode
    switch positional[0] {
    case "user": mode = .user
    case "pro": mode = .pro
    case "stage": mode = .stage
    case "piano": mode = .piano
    case "rainbow": mode = .rainbow
    default: printUsageAndExit()
    }
    send(LumiSysex.setColorMode(mode), destIndex: destFlag)

case "scale":
    guard positional.count == 1 else { printUsageAndExit() }
    let scale: LumiSysex.Scale
    switch positional[0] {
    case "major": scale = .major
    case "minor": scale = .minor
    case "harmonic-minor": scale = .harmonicMinor
    case "chromatic": scale = .chromatic
    case "pentatonic-neutral": scale = .pentatonicNeutral
    case "pentatonic-major": scale = .pentatonicMajor
    case "pentatonic-minor": scale = .pentatonicMinor
    case "blues": scale = .blues
    case "dorian": scale = .dorian
    case "phrygian": scale = .phrygian
    case "lydian": scale = .lydian
    case "mixolydian": scale = .mixolydian
    case "locrian": scale = .locrian
    case "whole-tone": scale = .wholeTone
    case "arabic-b": scale = .arabicB
    case "japanese": scale = .japanese
    case "ryukyu": scale = .ryukyu
    case "eight-tone-spanish": scale = .eightToneSpanish
    default: printUsageAndExit()
    }
    send(LumiSysex.setScale(scale), destIndex: destFlag)

case "key":
    guard positional.count == 1 else { printUsageAndExit() }
    let noteNames = ["C", "C#", "D", "D#", "E", "F", "F#", "G", "G#", "A", "A#", "B"]
    guard let pitchClass = noteNames.firstIndex(where: { $0.caseInsensitiveCompare(positional[0]) == .orderedSame }) else {
        printUsageAndExit()
    }
    send(LumiSysex.setKey(pitchClass: pitchClass), destIndex: destFlag)

case "reset":
    send(lumiResetBytes, destIndex: destFlag)

case "serial":
    send(lumiQuerySerialBytes, destIndex: destFlag)

case "raw":
    guard !positional.isEmpty else { printUsageAndExit() }
    var bytes: [UInt8] = []
    for token in positional {
        guard let byte = UInt8(token, radix: 16) else {
            print("Not a valid hex byte: \(token)")
            exit(1)
        }
        bytes.append(byte)
    }
    send(bytes, destIndex: destFlag)

default:
    printUsageAndExit()
}
