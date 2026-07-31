// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MusicTheoryKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "MusicTheoryKit", targets: ["MusicTheoryKit"]),
        .library(name: "PieceModel", targets: ["PieceModel"]),
        .library(name: "SoundTrackModel", targets: ["SoundTrackModel"]),
        .library(name: "SoundFontModel", targets: ["SoundFontModel"]),
        .library(name: "AudioEngine", targets: ["AudioEngine"]),
        .library(name: "MIDIEngine", targets: ["MIDIEngine"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "RecognitionEngine", targets: ["RecognitionEngine"]),
        .library(name: "LLMEngine", targets: ["LLMEngine"]),
        .library(name: "NetEngine", targets: ["NetEngine"]),
        .library(name: "WebConsole", targets: ["WebConsole"]),
        .library(name: "Localization", targets: ["Localization"]),
        .library(name: "JamShackUI", targets: ["JamShackUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
    ],
    targets: [
        .target(name: "MusicTheoryKit"),
        // FR/EN/DE UI text (`AppLanguage`, `L10nKey`, `L10n.string`) — zero dependencies, like
        // `WebConsole`/`NetEngine`, specifically so both `AppCore` AND `WebConsole` can depend on
        // it without `WebConsole` ever depending on `AppCore` (the reverse of the existing
        // dependency direction below) just to reach the shared translation table.
        .target(name: "Localization", resources: [.copy("Resources/L10nTable.json")]),
        .testTarget(name: "LocalizationTests", dependencies: ["Localization"]),
        .testTarget(name: "MusicTheoryKitTests", dependencies: ["MusicTheoryKit"]),
        .target(name: "PieceModel", dependencies: ["MusicTheoryKit", "SoundFontModel"]),
        .testTarget(name: "PieceModelTests", dependencies: ["PieceModel", "SoundFontModel"]),
        // A purely event-based (real-seconds) recording model — deliberately separate from
        // `PieceModel` (measures/beats/chords): incompatible shapes for the same underlying
        // idea of "musical content over time," not a variant of one another.
        .target(name: "SoundTrackModel"),
        .testTarget(name: "SoundTrackModelTests", dependencies: ["SoundTrackModel"]),
        // A `.sf2`'s own preset identity (`SoundFontPreset`/`SoundFontPresetIdentity`) plus the
        // RIFF/`phdr` reader that lists them — zero dependencies, like `SoundTrackModel`/
        // `Localization`, specifically so both `AudioEngine` (which maps a preset identity to
        // `AVAudioUnitSampler`'s bankMSB/bankLSB) AND `PieceModel` (which stores a track's chosen
        // preset) can depend on it without `PieceModel` ever depending on `AudioEngine` (which
        // itself already depends on `PieceModel` — a cycle otherwise).
        .target(name: "SoundFontModel"),
        .testTarget(name: "SoundFontModelTests", dependencies: ["SoundFontModel"]),
        .target(name: "AudioEngine", dependencies: ["PieceModel", "SoundTrackModel", "SoundFontModel"]),
        .testTarget(name: "AudioEngineTests", dependencies: ["AudioEngine", "SoundFontModel", "PieceModel"]),
        .target(name: "MIDIEngine"),
        .testTarget(name: "MIDIEngineTests", dependencies: ["MIDIEngine"]),
        .target(name: "RecognitionEngine", dependencies: ["MusicTheoryKit"]),
        .testTarget(name: "RecognitionEngineTests", dependencies: ["RecognitionEngine"]),
        .target(name: "LLMEngine", dependencies: ["MusicTheoryKit", "PieceModel", "SoundTrackModel"]),
        .testTarget(name: "LLMEngineTests", dependencies: ["LLMEngine", "MusicTheoryKit", "PieceModel", "SoundTrackModel"]),
        // Collaborative-session transport: a flat Codable message type plus a hand-rolled
        // length-prefixed TCP framing over Network.framework — no third-party dependency.
        .target(name: "NetEngine"),
        .testTarget(name: "NetEngineTests", dependencies: ["NetEngine"]),
        // Hand-rolled HTTP/1.1 server on Network.framework, serving the browser-based "Console
        // Web" — same "no third-party dependency" style as NetEngine, but HTTP instead of the
        // length-prefixed JSON framing. Deliberately knows nothing about ImprovSession/AppCore.
        .target(name: "WebConsole", dependencies: ["Localization"]),
        .testTarget(name: "WebConsoleTests", dependencies: ["WebConsole"]),
        // Presentation-agnostic app state/behavior: a CLI drives it today, a future
        // SwiftUI front-end can bind to the same `ImprovSession` instance later.
        .target(name: "AppCore", dependencies: [
            "MusicTheoryKit", "PieceModel", "SoundTrackModel", "SoundFontModel", "AudioEngine",
            "MIDIEngine", "RecognitionEngine", "LLMEngine", "NetEngine", "WebConsole", "Localization",
            // The embedded MCP server (macOS only, see `MCPServer.swift`) — the `MCP` product
            // itself pulls in only `swift-system`/`swift-log`/`eventsource`, never SwiftNIO
            // (that's only a dependency of the SDK's own example conformance-test executables,
            // which this target never references) — consistent with this codebase's existing
            // "no heavyweight third-party HTTP stack" preference (see `WebConsole`'s own doc
            // comment).
            .product(name: "MCP", package: "swift-sdk", condition: .when(platforms: [.macOS])),
        ]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "MIDIEngine", "MusicTheoryKit", "LLMEngine", "NetEngine", "SoundTrackModel", "SoundFontModel", "AudioEngine"]),
        .executableTarget(name: "JamShack", dependencies: ["AppCore", "Localization"]),
        // Standalone hardware-validation CLI for the ROLI LUMI Keys' reverse-engineered LED
        // SysEx protocol (see MIDIEngine's LumiSysex/MIDIOutputPort) — kept separate from
        // JamShack so poking at real hardware never risks ImprovSession's state/concurrency.
        .executableTarget(name: "LumiSpike", dependencies: ["MIDIEngine"]),
        // A tiny stdio<->HTTP bridge for Claude Desktop, which (confirmed empirically — see
        // `MCPServer.swift`'s own doc comment) only accepts a `"command"` (stdio-spawned)
        // entry in `claude_desktop_config.json`, never a bare `"url"` one, even though MCP's
        // own Streamable HTTP transport is otherwise a perfectly valid, spec-compliant choice.
        // Deliberately protocol-agnostic (no dependency on the `MCP` SDK, or even on
        // `AppCore`): MCP's Streamable HTTP wire format already carries the exact same
        // JSON-RPC 2.0 messages stdio does, just framed differently (one HTTP POST body vs.
        // one newline-delimited line) — this only needs to translate between the two framings,
        // never parse or understand a single MCP message itself. All the real logic (tool
        // list, dispatch into `ImprovSession`) stays in the already-running `JamShackApp` GUI
        // process's own embedded `MCPServer`; this is just a dumb pipe Claude Desktop can spawn.
        .executableTarget(name: "JamShackMCPBridge"),
        // Shared SwiftUI component library (iOS + macOS, visionOS later) consumed by the
        // JamShackApp Xcode project (App/JamShackApp.xcodeproj) — kept as a plain SPM target,
        // not inside the app project itself, so it stays independently buildable/previewable
        // and testable without opening Xcode. Named JamShackUI rather than "JamShack" since
        // that name is already taken by the CLI executableTarget above (SPM target names must
        // be unique) — same disambiguation-by-suffix convention as MusicTheoryKit itself.
        .target(name: "JamShackUI", dependencies: ["AppCore", "Localization"]),
        .testTarget(name: "JamShackUITests", dependencies: ["JamShackUI"]),
    ]
)
