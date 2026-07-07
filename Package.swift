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
        .library(name: "AudioEngine", targets: ["AudioEngine"]),
        .library(name: "MIDIEngine", targets: ["MIDIEngine"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "RecognitionEngine", targets: ["RecognitionEngine"]),
        .library(name: "LLMEngine", targets: ["LLMEngine"]),
        .library(name: "NetEngine", targets: ["NetEngine"]),
    ],
    targets: [
        .target(name: "MusicTheoryKit"),
        .testTarget(name: "MusicTheoryKitTests", dependencies: ["MusicTheoryKit"]),
        .target(name: "PieceModel", dependencies: ["MusicTheoryKit"]),
        .testTarget(name: "PieceModelTests", dependencies: ["PieceModel"]),
        // A purely event-based (real-seconds) recording model — deliberately separate from
        // `PieceModel` (measures/beats/chords): incompatible shapes for the same underlying
        // idea of "musical content over time," not a variant of one another.
        .target(name: "SoundTrackModel"),
        .testTarget(name: "SoundTrackModelTests", dependencies: ["SoundTrackModel"]),
        .target(name: "AudioEngine", dependencies: ["PieceModel", "SoundTrackModel"]),
        .testTarget(name: "AudioEngineTests", dependencies: ["AudioEngine"]),
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
        // Presentation-agnostic app state/behavior: a CLI drives it today, a future
        // SwiftUI front-end can bind to the same `ImprovSession` instance later.
        .target(name: "AppCore", dependencies: ["MusicTheoryKit", "PieceModel", "SoundTrackModel", "AudioEngine", "MIDIEngine", "RecognitionEngine", "LLMEngine", "NetEngine"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "MIDIEngine", "MusicTheoryKit", "LLMEngine", "NetEngine", "SoundTrackModel"]),
        .executableTarget(name: "ImprovCLI", dependencies: ["AppCore"]),
        .executableTarget(name: "SanityChecks", dependencies: ["MusicTheoryKit", "PieceModel", "SoundTrackModel", "AudioEngine", "MIDIEngine", "AppCore", "RecognitionEngine", "LLMEngine", "NetEngine"]),
    ]
)
