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
        .library(name: "AudioEngine", targets: ["AudioEngine"]),
        .library(name: "MIDIEngine", targets: ["MIDIEngine"]),
        .library(name: "AppCore", targets: ["AppCore"]),
        .library(name: "RecognitionEngine", targets: ["RecognitionEngine"]),
        .library(name: "LLMEngine", targets: ["LLMEngine"]),
    ],
    targets: [
        .target(name: "MusicTheoryKit"),
        .testTarget(name: "MusicTheoryKitTests", dependencies: ["MusicTheoryKit"]),
        .target(name: "PieceModel", dependencies: ["MusicTheoryKit"]),
        .testTarget(name: "PieceModelTests", dependencies: ["PieceModel"]),
        .target(name: "AudioEngine", dependencies: ["PieceModel"]),
        .target(name: "MIDIEngine"),
        .testTarget(name: "MIDIEngineTests", dependencies: ["MIDIEngine"]),
        .target(name: "RecognitionEngine", dependencies: ["MusicTheoryKit"]),
        .testTarget(name: "RecognitionEngineTests", dependencies: ["RecognitionEngine"]),
        .target(name: "LLMEngine", dependencies: ["MusicTheoryKit", "PieceModel"]),
        .testTarget(name: "LLMEngineTests", dependencies: ["LLMEngine", "MusicTheoryKit", "PieceModel"]),
        // Presentation-agnostic app state/behavior: a CLI drives it today, a future
        // SwiftUI front-end can bind to the same `ImprovSession` instance later.
        .target(name: "AppCore", dependencies: ["MusicTheoryKit", "PieceModel", "AudioEngine", "MIDIEngine", "RecognitionEngine", "LLMEngine"]),
        .testTarget(name: "AppCoreTests", dependencies: ["AppCore", "MIDIEngine", "MusicTheoryKit", "LLMEngine"]),
        .executableTarget(name: "ImprovCLI", dependencies: ["AppCore"]),
        .executableTarget(name: "SanityChecks", dependencies: ["MusicTheoryKit", "PieceModel", "MIDIEngine", "AppCore", "RecognitionEngine", "LLMEngine"]),
    ]
)
