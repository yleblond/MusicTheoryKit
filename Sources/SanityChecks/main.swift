import MusicTheoryKit
import PieceModel
@testable import AudioEngine
import MIDIEngine
@testable import AppCore
import RecognitionEngine
@testable import LLMEngine
@testable import NetEngine
@testable import SoundTrackModel
@testable import WebConsole
import Localization
import Foundation

// Mirrors the same helper in Tests/AppCoreTests/ImprovSessionTests.swift — compares by
// description so a new SessionError case doesn't also require updating this.
extension ImprovSession.SessionError: Equatable {
    public static func == (lhs: ImprovSession.SessionError, rhs: ImprovSession.SessionError) -> Bool {
        lhs.description == rhs.description
    }
}

// Stand-in for the real XCTest suites in Tests/PieceModelTests (which this file mirrors
// case-for-case): this machine has no Xcode, only Command Line Tools, so `swift test`
// fails with "no such module 'XCTest'". Run with `swift run SanityChecks`. If you ever
// install full Xcode, prefer `swift test` (or Xcode's test navigator) and let this file
// go stale — it's a workaround, not a replacement.

// Unbuffered: if a check ever crashes the process (a real concurrency bug did, once —
// see ImprovSession.playbackStateQueue), the fully-buffered default would swallow every
// check printed before the crash, making the failure look like silent, output-less death.
setvbuf(stdout, nil, _IONBF, 0)

nonisolated(unsafe) var checks = 0
nonisolated(unsafe) var failures = 0

func check<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
    checks += 1
    if actual != expected {
        failures += 1
        print("FAIL [\(label)]: expected \(expected), got \(actual)")
    }
}

func checkNil<T>(_ actual: T?, _ label: String) {
    checks += 1
    if actual != nil {
        failures += 1
        print("FAIL [\(label)]: expected nil, got \(String(describing: actual))")
    }
}

func checkNotNil<T>(_ actual: T?, _ label: String) {
    checks += 1
    if actual == nil {
        failures += 1
        print("FAIL [\(label)]: expected non-nil")
    }
}

// MARK: - ImprovSessionTests (mirrors Tests/AppCoreTests/ImprovSessionTests.swift)

func testLoadDemoPieceSetsPieceAndLogsIt() {
    let session = ImprovSession()
    checkNil(session.piece, "improv session starts with no piece")
    session.loadDemoPiece()
    check(session.piece?.title, "ii-V-I demo", "improv session load-demo sets piece title")
    checks += 1
    if !session.log.contains(where: { $0.contains("ii-V-I demo") }) {
        failures += 1
        print("FAIL [improv session load-demo logs it]: \(session.log)")
    }
}

func testPlayWithoutAPieceLoadedThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.play()
        failures += 1
        print("FAIL [improv session play without piece throws]: did not throw")
    } catch {
        // expected
    }
}

func testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished() {
    do {
        let session = ImprovSession()
        try session.start()

        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [ChordEvent(measure: 1, beat: 1, durationBeats: 1, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))]
        )
        // A very fast tempo so playback finishes almost immediately and this check doesn't
        // need to sleep long to observe the "cleared after finishing" half of the behavior.
        let piece = Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        try session.play()
        check(session.isPlaying, true, "play sets isPlaying")
        check(session.playbackTimeline.count, 1, "play populates playbackTimeline")
        check(session.playbackTimeline.first?.chord, ChordReference(root: 0, chordTemplateID: "Ma7"), "playbackTimeline carries the chord")
        check(session.playbackCurrentChordIndex, 0, "play starts at chord index 0")

        Thread.sleep(forTimeInterval: 0.5)
        check(session.isPlaying, false, "playback finished clears isPlaying")
        checkNil(session.playbackCurrentChordIndex, "playback finished clears playbackCurrentChordIndex")
        check(session.playbackHeldPitches, [], "playback finished clears playbackHeldPitches")
    } catch {
        failures += 1
        print("FAIL [play tracks playback state]: threw \(error)")
    }
}

func loadTemporaryPiece(_ piece: Piece, into session: ImprovSession) throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    try JSONEncoder().encode(piece).write(to: url)
    try session.loadPiece(fromJSONFile: url.path)
}

func testSetPieceTrackInstrumentUpdatesTrackAndLogs() {
    do {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: "mcb.sf2")

        check(session.piece?.sections[0].tracks[0].instrument, "mcb.sf2", "setPieceTrackInstrument updates the track's instrument")
        checks += 1
        if !session.log.contains(where: { $0.contains("mcb.sf2") }) {
            failures += 1
            print("FAIL [setPieceTrackInstrument logs it]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument updates track and logs]: threw \(error)")
    }
}

func testSetPieceTrackInstrumentNilRevertsToEmptyString() {
    do {
        let session = ImprovSession()
        let track = Track(name: "lead", instrument: "mcb.sf2")
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "t", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 0, instrumentName: nil)

        check(session.piece?.sections[0].tracks[0].instrument, "", "setPieceTrackInstrument(nil) reverts to empty string")
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument nil reverts]: threw \(error)")
    }
}

func testSetPieceTrackInstrumentWithInvalidSectionIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceTrackInstrument(sectionIndex: 99, trackIndex: 0, instrumentName: "mcb.sf2")
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid section throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceSectionIndex {
            failures += 1
            print("FAIL [setPieceTrackInstrument invalid section throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid section throws]: unexpected error \(error)")
    }
}

func testSetPieceTrackInstrumentWithInvalidTrackIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceTrackInstrument(sectionIndex: 0, trackIndex: 99, instrumentName: "mcb.sf2")
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid track throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceTrackIndex {
            failures += 1
            print("FAIL [setPieceTrackInstrument invalid track throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceTrackInstrument invalid track throws]: unexpected error \(error)")
    }
}

func testSetPieceChordInstrumentUpdatesSectionAndLogs() {
    do {
        let session = ImprovSession()
        session.loadDemoPiece()
        try session.setPieceChordInstrument(sectionIndex: 0, instrumentName: "strings.sf2")
        check(session.piece?.sections[0].chordInstrument, "strings.sf2", "setPieceChordInstrument updates the section's chord instrument")
        checks += 1
        if !session.log.contains(where: { $0.contains("strings.sf2") }) {
            failures += 1
            print("FAIL [setPieceChordInstrument logs it]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceChordInstrument updates section and logs]: threw \(error)")
    }
}

func testSetPieceChordInstrumentWithInvalidSectionIndexThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.setPieceChordInstrument(sectionIndex: 99, instrumentName: "strings.sf2")
        failures += 1
        print("FAIL [setPieceChordInstrument invalid section throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .invalidPieceSectionIndex {
            failures += 1
            print("FAIL [setPieceChordInstrument invalid section throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [setPieceChordInstrument invalid section throws]: unexpected error \(error)")
    }
}

func testPlayWarnsWhenATracksInstrumentFileIsNotFound() {
    do {
        let session = ImprovSession()
        try session.start()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try session.listSampleFiles(in: folder.path)

        let track = Track(name: "lead", instrument: "does-not-exist.sf2", melodyEvents: [MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60)])
        let section = Section(name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"), tracks: [track])
        try loadTemporaryPiece(Piece(title: "fast", tempoBPM: 6000, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section]), into: session)

        try session.play()

        checks += 1
        if !session.log.contains(where: { $0.contains("does-not-exist.sf2") && $0.contains("introuvable") }) {
            failures += 1
            print("FAIL [play warns on missing track instrument]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [play warns when instrument file is not found]: threw \(error)")
    }
}

func testPlayWithoutAnyTrackInstrumentLogsNoInstrumentWarning() {
    do {
        let session = ImprovSession()
        try session.start()
        session.loadDemoPiece()
        try session.play()
        Thread.sleep(forTimeInterval: 0.1)
        checks += 1
        if session.log.contains(where: { $0.hasPrefix("Instrument:") }) {
            failures += 1
            print("FAIL [play without instruments logs no warning]: \(session.log)")
        }
    } catch {
        failures += 1
        print("FAIL [play without any track instrument]: threw \(error)")
    }
}

func testStartTrackOnAnUnlistedMIDIPortThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        // A huge index, not 0: default fusion mode is `.individual` now, and this machine
        // does have at least one real MIDI source visible to CoreMIDI, so `.midiSource(0)`
        // can legitimately already be a listed track — the point of this test is "an index
        // with no matching track throws", which an index this large guarantees regardless
        // of how many real MIDI ports happen to be attached.
        try session.startTrack(.midiSource(9999))
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: did not throw")
    } catch ImprovSession.SessionError.unknownTrack {
        // expected
    } catch {
        failures += 1
        print("FAIL [start-track on unlisted MIDI port throws]: wrong error \(error)")
    }
}

func testDefaultMIDIFusionModeIsIndividual() {
    // Individual (one track per visible MIDI port), not merged — see `midiFusionMode`'s own
    // doc comment for why: a per-port track is what lets the LUMI run-mode integration
    // single out the LUMI's own track by name. This machine has no MIDI hardware attached,
    // so `.midiSource` tracks are simply absent rather than assertable one way or the other.
    let session = ImprovSession()
    check(session.midiFusionMode, MIDIFusionMode.individual, "default MIDI fusion mode is individual")
    check(session.tracks.contains { $0.id == .computerKeyboard }, true, "tracks always include the computer keyboard")
    check(session.tracks.contains { $0.id == .microphone }, true, "tracks always include the microphone")
}

func testSetMIDIFusionModeSwitchesTrackList() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.individual)
    check(session.midiFusionMode, MIDIFusionMode.individual, "setMIDIFusionMode updates midiFusionMode")
    check(session.tracks.contains { $0.id == .midiMerged }, false, "individual mode drops the midiMerged track")
    check(session.tracks.contains { $0.id == .computerKeyboard }, true, "individual mode still lists the computer keyboard")
    check(session.tracks.contains { $0.id == .microphone }, true, "individual mode still lists the microphone")
}

func testMicrophoneTrackCannotHaveSound() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.setSoundEnabled(true, for: .microphone)
        failures += 1
        print("FAIL [microphone track cannot have sound]: did not throw")
    } catch ImprovSession.SessionError.trackCannotHaveSound {
        // expected
    } catch {
        failures += 1
        print("FAIL [microphone track cannot have sound]: wrong error \(error)")
    }
}

func testSetMicrophoneRecognitionModeRejectsNonMicrophoneTrack() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .computerKeyboard)
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode rejects non-microphone track]: did not throw")
    } catch ImprovSession.SessionError.recognitionModeOnlyForMicrophone {
        // expected
    } catch {
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode rejects non-microphone track]: wrong error \(error)")
    }
}

func testSetMicrophoneRecognitionModeRejectsInvalidWindowCount() {
    let session = ImprovSession()
    for mode: MicrophoneRecognitionMode in [.polyphonicLatched(windows: 0), .polyphonicSliding(windows: 0)] {
        checks += 1
        do {
            try session.setMicrophoneRecognitionMode(mode, for: .microphone)
            failures += 1
            print("FAIL [setMicrophoneRecognitionMode rejects invalid window count]: did not throw for \(mode)")
        } catch ImprovSession.SessionError.invalidRecognitionWindowCount {
            // expected
        } catch {
            failures += 1
            print("FAIL [setMicrophoneRecognitionMode rejects invalid window count]: wrong error \(error)")
        }
    }
}

func testSetMicrophoneRecognitionModeSurvivesTrackRestart() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHPS, for: .microphone)
        try session.startTrack(.microphone)
        check(session.tracks.first { $0.id == .microphone }?.microphoneRecognitionMode, .monophonicHPS, "mode set before listening survives startTrack")
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 4), for: .microphone)
        let track = session.tracks.first { $0.id == .microphone }
        check(track?.microphoneRecognitionMode, .polyphonicSliding(windows: 4), "mode changed while listening takes effect")
        check(track?.isListening, true, "track still listening after a live mode change (restart)")
    } catch {
        failures += 1
        print("FAIL [setMicrophoneRecognitionMode survives track restart]: threw \(error)")
    }
}

func testMicrophonePolyLatchedDoesNotConfirmAFlickeringNote() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicLatched(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [poly-latched does not confirm a flickering note]: pitch 60 was confirmed")
        }
    } catch {
        failures += 1
        print("FAIL [poly-latched does not confirm a flickering note]: threw \(error)")
    }
}

func testMicrophonePolySlidingConfirmsUnderMajorityDespiteOneDropout() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.polyphonicSliding(windows: 3), for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([], level: 0.1, track: .microphone)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if !session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [poly-sliding confirms under majority despite one dropout]: pitch 60 was not confirmed")
        }
    } catch {
        failures += 1
        print("FAIL [poly-sliding confirms under majority despite one dropout]: threw \(error)")
    }
}

func testMicrophoneMonophonicModeConfirmsImmediately() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.setMicrophoneRecognitionMode(.monophonicHeuristic, for: .microphone)
        try session.startTrack(.microphone)
        let pitch = DetectedPitch(frequencyHz: 261.63, midiPitch: 60)
        session.simulateMicrophoneDetection([pitch], level: 0.1, track: .microphone)
        if !session.tracks.first(where: { $0.id == .microphone })!.heldPitches.contains(60) {
            failures += 1
            print("FAIL [monophonic mode confirms immediately]: pitch 60 was not confirmed after one window")
        }
    } catch {
        failures += 1
        print("FAIL [monophonic mode confirms immediately]: threw \(error)")
    }
}

func testNetMessageRoundTripsThroughJSON() {
    checks += 1
    do {
        let original = NetMessage(kind: .noteEvent, clientID: "abc", trackID: "clavier", isNoteOn: true, pitch: 60, velocity: 100, channel: 0)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(NetMessage.self, from: data)
        check(decoded, original, "NetMessage round-trips through JSON")
    } catch {
        failures += 1
        print("FAIL [NetMessage round trip]: threw \(error)")
    }
}
testNetMessageRoundTripsThroughJSON()

// A real client/server pair over real loopback TCP, both `ImprovSession` instances living
// in this one process — not a mock, and not a pty-driven external test: exercises the
// actual `NetworkServer`/`NetworkClient`/`FramedConnection` wire path end to end. Port
// 17891 is arbitrary; a rerun failing specifically with "address already in use" points at
// the OS not having released it yet from a previous run, not a logic bug.
func testCollaborativeServerClientSyncsTracksAndRecognition() {
    checks += 1
    do {
        let server = ImprovSession()
        try server.start()
        server.localClientName = "Alice"
        let client = ImprovSession()
        try client.start()
        client.localClientName = "Bob"
        let port = 17891

        try server.startServer(port: port)
        try client.connectToServer(host: "127.0.0.1", port: port)
        Thread.sleep(forTimeInterval: 0.3) // TCP handshake + hello

        try server.startTrack(.computerKeyboard)
        for pitch in [62, 66, 69] { server.pressKey(pitch: pitch) } // D F# A -> D major

        try client.startTrack(.computerKeyboard)
        for pitch in [60, 64, 67] { client.pressKey(pitch: pitch) } // C E G -> C major

        Thread.sleep(forTimeInterval: 0.6) // noteEvent -> server recognizes -> next sync tick -> client merges

        let clientTrackOnServer = TrackID.remote(clientID: client.localClientID, trackID: "clavier")
        if let mirrored = server.tracks.first(where: { $0.id == clientTrackOnServer }) {
            check(mirrored.recognizedChord?.chordTemplateID, "Ma", "server recognizes the client's forwarded C major triad")
            check(mirrored.ownerName, "Bob", "server labels the client's track with the client's pseudo")
        } else {
            failures += 1
            print("FAIL [server/client sync]: server never saw the client's 'clavier' track")
        }

        let serverTrackOnClient = TrackID.remote(clientID: server.localClientID, trackID: "clavier")
        if let mirrored = client.tracks.first(where: { $0.id == serverTrackOnClient }) {
            let hasChordText = mirrored.remoteChordDisplay?.contains("Ma") ?? false
            check(hasChordText, true, "client mirrors the server's own track with a display-string chord")
            check(mirrored.ownerName, "Alice", "client labels the server's own track with the server's pseudo")
        } else {
            failures += 1
            print("FAIL [server/client sync]: client never saw the server's own 'clavier' track")
        }

        server.stopServer()
        client.disconnectFromServer()
        Thread.sleep(forTimeInterval: 0.1)
        check(server.tracks.contains { if case .remote = $0.id { return true }; return false }, false, "stopServer clears every remote track")
        check(client.tracks.contains { if case .remote = $0.id { return true }; return false }, false, "disconnectFromServer clears every remote track")
    } catch {
        failures += 1
        print("FAIL [server/client sync]: threw \(error)")
    }
}
testCollaborativeServerClientSyncsTracksAndRecognition()

// Mirrors Tests/AppCoreTests/ImprovSessionTests.swift's web-console guard-clause tests.
func testStartWebConsoleSetsPortAndStopClearsIt() {
    checks += 1
    do {
        let session = ImprovSession()
        checkNil(session.webConsolePort, "webConsolePort starts nil")
        try session.startWebConsole(port: 18391)
        check(session.webConsolePort, 18391, "webConsolePort set after start")
        session.stopWebConsole()
        checkNil(session.webConsolePort, "webConsolePort cleared after stop")
    } catch {
        failures += 1
        print("FAIL [web console start/stop]: threw \(error)")
    }
}
testStartWebConsoleSetsPortAndStopClearsIt()

func testStartWebConsoleTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startWebConsole(port: 18392)
        defer { session.stopWebConsole() }
        do {
            try session.startWebConsole(port: 18393)
            failures += 1
            print("FAIL [web console double start]: did not throw")
        } catch ImprovSession.SessionError.webConsoleAlreadyActive {
            // expected
        } catch {
            failures += 1
            print("FAIL [web console double start]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [web console double start]: setup threw \(error)")
    }
}
testStartWebConsoleTwiceThrows()

func testStartWebConsoleInvalidPortThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startWebConsole(port: 999_999)
        failures += 1
        print("FAIL [web console invalid port]: did not throw")
    } catch {
        // expected
    }
    checkNil(session.webConsolePort, "webConsolePort stays nil after a failed start")
}
testStartWebConsoleInvalidPortThrows()

// A real HTTP round trip over real loopback TCP against the actual `HTTPServer` — not a
// mock — exercising the exact bug this feature hit during manual verification: an
// `HTTPConnection` created as a local in `newConnectionHandler` with only weak-self
// callbacks was deallocated before it could ever answer, and `HTTPServer.stop()`'s
// `[weak self]` queue.async raced the caller's immediate `= nil` and never actually
// cancelled the listener. Port 18394 is arbitrary, same caveat as the collaborative test's
// own fixed port.
// Mirrors Tests/WebConsoleTests/HTTPWireFormatTests.swift.
func testParseRequestLineExtractsMethodAndPath() {
    let request = HTTPWireFormat.parseRequestLine("GET /state HTTP/1.1\r\nHost: localhost\r\n")
    check(request?.method, "GET", "parseRequestLine extracts the method")
    check(request?.path, "/state", "parseRequestLine extracts the path")
}
testParseRequestLineExtractsMethodAndPath()

func testParseRequestLineRejectsMalformedLine() {
    // Deliberately lenient (no method whitelist, no HTTP-version check — see its doc
    // comment): the only real guard is "at least a method and a path", so only a line with
    // fewer than two space-separated tokens counts as malformed here.
    checkNil(HTTPWireFormat.parseRequestLine("GET"), "parseRequestLine rejects a line with no path")
    checkNil(HTTPWireFormat.parseRequestLine(""), "parseRequestLine rejects an empty line")
}
testParseRequestLineRejectsMalformedLine()

func testResponseHeadIncludesContentLengthAndCloseConnection() {
    let response = HTTPResponse.text("hello", contentType: "text/plain")
    let head = HTTPWireFormat.responseHead(for: response)
    check(head.hasPrefix("HTTP/1.1 200 OK\r\n"), true, "responseHead starts with the status line")
    check(head.contains("Content-Type: text/plain\r\n"), true, "responseHead includes Content-Type")
    check(head.contains("Content-Length: 5\r\n"), true, "responseHead includes Content-Length")
    check(head.contains("Connection: close\r\n"), true, "responseHead includes Connection: close")
    check(head.hasSuffix("\r\n\r\n"), true, "responseHead ends with the blank line terminating headers")
}
testResponseHeadIncludesContentLengthAndCloseConnection()

func testNotFoundResponseIs404() {
    check(HTTPResponse.notFound().status, 404, "HTTPResponse.notFound() is a 404")
}
testNotFoundResponseIs404()

func syncGET(_ url: String, timeout: TimeInterval = 2) -> (status: Int, contentType: String?, body: String)? {
    let semaphore = DispatchSemaphore(value: 0)
    nonisolated(unsafe) var result: (Int, String?, String)?
    URLSession.shared.dataTask(with: URL(string: url)!) { data, response, _ in
        if let http = response as? HTTPURLResponse, let data {
            result = (http.statusCode, http.value(forHTTPHeaderField: "Content-Type"), String(data: data, encoding: .utf8) ?? "")
        }
        semaphore.signal()
    }.resume()
    _ = semaphore.wait(timeout: .now() + timeout)
    return result
}

func testWebConsoleServesPageScriptAndState() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startWebConsole(port: 18394)
        try session.startTrack(.computerKeyboard)
        session.pressKey(pitch: 60)
        session.pressKey(pitch: 64)
        session.pressKey(pitch: 67)
        Thread.sleep(forTimeInterval: 0.3) // let the 150ms refresh timer tick at least once

        if let page = syncGET("http://127.0.0.1:18394/") {
            check(page.status, 200, "GET / returns 200")
            check(page.contentType?.contains("text/html") ?? false, true, "GET / is HTML")
        } else {
            failures += 1
            print("FAIL [web console GET /]: no response")
        }

        if let script = syncGET("http://127.0.0.1:18394/app.js") {
            check(script.status, 200, "GET /app.js returns 200")
            check(script.contentType ?? "", "application/javascript", "GET /app.js content type")
        } else {
            failures += 1
            print("FAIL [web console GET /app.js]: no response")
        }

        if let state = syncGET("http://127.0.0.1:18394/state") {
            check(state.status, 200, "GET /state returns 200")
            check(state.body.contains("\"chordRoot\":0"), true, "GET /state reflects the C major triad just played")
            check(state.body.contains("\"id\":\"clavier\""), true, "GET /state includes the listening track")
        } else {
            failures += 1
            print("FAIL [web console GET /state]: no response")
        }

        if let notFound = syncGET("http://127.0.0.1:18394/nope") {
            check(notFound.status, 404, "GET /nope returns 404")
        } else {
            failures += 1
            print("FAIL [web console GET /nope]: no response")
        }

        session.stopWebConsole()
        Thread.sleep(forTimeInterval: 0.2)
        check(syncGET("http://127.0.0.1:18394/state", timeout: 1) == nil, true, "stopWebConsole actually releases the port")
    } catch {
        failures += 1
        print("FAIL [web console HTTP round trip]: threw \(error)")
    }
}
testWebConsoleServesPageScriptAndState()

// No `.webKeyboard(clientID:)` track is pre-created at all anymore — unlike the computer
// keyboard, it's created on demand per browser the first time that browser's `clientID`
// shows up in a request (see `ensureWebKeyboardTrack`), so `startVirtualKeyboard` on its own
// leaves `tracks` unchanged; only an actual `GET` with `?client=...` creates one, and
// `stopVirtualKeyboard` drops every such track regardless of client.
func testStartVirtualKeyboardSetsPortAndStopRemovesAnyConnectedClientTracks() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        checkNil(session.virtualKeyboardPort, "virtualKeyboardPort starts nil")
        try session.startVirtualKeyboard(port: 18395)
        check(session.virtualKeyboardPort, 18395, "virtualKeyboardPort set after start")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, false, "starting the server alone creates no .webKeyboard track yet")
        _ = syncGET("http://127.0.0.1:18395/note-on?pitch=60&client=test-client-1&name=Alice")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, true, "a request with ?client=... creates its track on demand")
        session.stopVirtualKeyboard()
        checkNil(session.virtualKeyboardPort, "virtualKeyboardPort cleared after stop")
        check(session.tracks.contains { if case .webKeyboard = $0.id { return true }; return false }, false, "stopVirtualKeyboard removes every connected client's track")
    } catch {
        failures += 1
        print("FAIL [virtual keyboard start/stop]: threw \(error)")
    }
}
testStartVirtualKeyboardSetsPortAndStopRemovesAnyConnectedClientTracks()

func testStartVirtualKeyboardTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startVirtualKeyboard(port: 18396)
        defer { session.stopVirtualKeyboard() }
        do {
            try session.startVirtualKeyboard(port: 18397)
            failures += 1
            print("FAIL [virtual keyboard double start]: did not throw")
        } catch ImprovSession.SessionError.virtualKeyboardAlreadyActive {
            // expected
        } catch {
            failures += 1
            print("FAIL [virtual keyboard double start]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [virtual keyboard double start]: setup threw \(error)")
    }
}
testStartVirtualKeyboardTwiceThrows()

// Real HTTP round trip over real loopback TCP — note-on/note-off through the actual
// `GET /note-on`/`GET /note-off` routes (not `session.pressKey` directly), since the whole
// point is verifying the HTTP-to-session wiring, mirroring `testWebConsoleServesPageScriptAndState`.
func testVirtualKeyboardServesPageAndAcceptsNoteOnOff() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18398)

        if let page = syncGET("http://127.0.0.1:18398/") {
            check(page.status, 200, "GET / returns 200")
            check(page.contentType?.contains("text/html") ?? false, true, "GET / is HTML")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /]: no response")
        }

        if let script = syncGET("http://127.0.0.1:18398/app.js") {
            check(script.status, 200, "GET /app.js returns 200")
            check(script.contentType ?? "", "application/javascript", "GET /app.js content type")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /app.js]: no response")
        }

        if let noClient = syncGET("http://127.0.0.1:18398/state") {
            check(noClient.status, 400, "GET /state with no ?client=... returns 400")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state no client]: no response")
        }

        let alice = "&client=alice-uuid&name=Alice"
        if let before = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(before.body.contains("\"heldPitches\":[]"), true, "GET /state starts with no held pitches")
            check(before.body.contains("\"label\":\"Alice\""), true, "GET /state reports the chosen alias as the track's label")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state before note-on]: no response")
        }

        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        if let held = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(held.body.contains("\"chordRoot\":0"), true, "GET /note-on drove the session — C major triad recognized")
            check(held.body.contains("\"id\":\"clavier-web:alice-uuid\""), true, "GET /state reports this client's own dedicated track id")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after note-on]: no response")
        }

        // A second, unrelated client (different `?client=...`) must get its OWN independent
        // track — no cross-talk between the two connected browsers.
        let bob = "&client=bob-uuid&name=Bob"
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=62" + bob)
        Thread.sleep(forTimeInterval: 0.2)
        if let bobState = syncGET("http://127.0.0.1:18398/state?dummy=1" + bob), let aliceState = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(bobState.body.contains("\"heldPitches\":[62]"), true, "the second client's own track only has its own note held")
            check(aliceState.body.contains("\"heldPitches\":[60,64,67]") || aliceState.body.contains("\"heldPitches\":[60,67,64]") || aliceState.body.contains("\"heldPitches\":[64,60,67]") || aliceState.body.contains("\"heldPitches\":[64,67,60]") || aliceState.body.contains("\"heldPitches\":[67,60,64]") || aliceState.body.contains("\"heldPitches\":[67,64,60]"), true, "the first client's track is untouched by the second client's note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard two clients]: no response")
        }

        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=60" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=64" + alice)
        _ = syncGET("http://127.0.0.1:18398/note-off?pitch=67" + alice)
        Thread.sleep(forTimeInterval: 0.2)

        if let released = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(released.body.contains("\"heldPitches\":[]"), true, "GET /note-off released every note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after note-off]: no response")
        }

        // The Escape "panic button" route — simulates a note stuck held (as if its matching
        // note-off had raced and lost, see `releaseAllKeys`'s doc comment) and confirms
        // GET /release-all clears it without needing to know which pitch was stuck.
        _ = syncGET("http://127.0.0.1:18398/note-on?pitch=72" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        _ = syncGET("http://127.0.0.1:18398/release-all?dummy=1" + alice)
        Thread.sleep(forTimeInterval: 0.2)
        if let afterReleaseAll = syncGET("http://127.0.0.1:18398/state?dummy=1" + alice) {
            check(afterReleaseAll.body.contains("\"heldPitches\":[]"), true, "GET /release-all clears a stuck-held note")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /state after release-all]: no response")
        }

        if let badPitch = syncGET("http://127.0.0.1:18398/note-on?pitch=notanumber" + alice) {
            check(badPitch.status, 400, "GET /note-on with a non-numeric pitch returns 400")
        } else {
            failures += 1
            print("FAIL [virtual keyboard GET /note-on bad pitch]: no response")
        }

        session.stopVirtualKeyboard()
        Thread.sleep(forTimeInterval: 0.2)
        check(syncGET("http://127.0.0.1:18398/state" + alice, timeout: 1) == nil, true, "stopVirtualKeyboard actually releases the port")
    } catch {
        failures += 1
        print("FAIL [virtual keyboard HTTP round trip]: threw \(error)")
    }
}
testVirtualKeyboardServesPageAndAcceptsNoteOnOff()

func testVirtualKeyboardStateAlwaysIncludesWheelButOnlyGuideWhileActive() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18399)
        let client = "&client=guide-client&name=Guidee"

        if let noGuide = syncGET("http://127.0.0.1:18399/state?dummy=1" + client) {
            // Synthesized `Encodable` conformance uses `encodeIfPresent` for `Optional`
            // properties — a `nil` field is OMITTED from the JSON entirely, not written as
            // an explicit `null`, so the absence check is on the key itself.
            check(noGuide.body.contains("\"guide\""), false, "no guide running — guide key is omitted")
            // `wheel` is now always present (like the read-only console's own) — the virtual
            // keyboard page shows it, and lets you click chords on it, whether or not a guide
            // is running; only rendering the mode-relative parts is gated client-side.
            check(noGuide.body.contains("\"wheel\""), true, "no guide running — wheel key is still present")
        } else {
            failures += 1
            print("FAIL [virtual keyboard no guide]: no response")
        }

        session.newGuideSequence(title: "Test")
        try session.addGuideStep(ModeReference(tonic: 9, scaleID: "lydian")) // A Lydian
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        if let withGuide = syncGET("http://127.0.0.1:18399/state?dummy=1" + client) {
            check(withGuide.body.contains("\"isActive\":true"), true, "guide running — guide.isActive is true")
            check(withGuide.body.contains("\"activeModeName\":\"Lydian\""), true, "guide running — wheel reflects the guide's own mode, not this track's")
        } else {
            failures += 1
            print("FAIL [virtual keyboard with guide]: no response")
        }

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard guide/wheel]: threw \(error)")
    }
}
testVirtualKeyboardStateAlwaysIncludesWheelButOnlyGuideWhileActive()

func testVirtualKeyboardGuideAdvanceMovesTheSharedGuideStep() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18410)
        let client = "&client=advance-client&name=Advancer"

        session.newGuideSequence(title: "Advance Test")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()
        check(session.currentGuideStepIndex, 0, "guide starts at step 0")

        if let advanced = syncGET("http://127.0.0.1:18410/guide-advance?delta=1" + client) {
            check(advanced.status, 200, "GET /guide-advance?delta=1 succeeds")
        } else {
            failures += 1
            print("FAIL [guide-advance forward]: no response")
        }
        check(session.currentGuideStepIndex, 1, "GET /guide-advance?delta=1 moves the shared guide forward")

        if let back = syncGET("http://127.0.0.1:18410/guide-advance?delta=-1" + client) {
            check(back.status, 200, "GET /guide-advance?delta=-1 succeeds")
        } else {
            failures += 1
            print("FAIL [guide-advance backward]: no response")
        }
        check(session.currentGuideStepIndex, 0, "GET /guide-advance?delta=-1 moves the shared guide backward")

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard guide-advance]: threw \(error)")
    }
}
testVirtualKeyboardGuideAdvanceMovesTheSharedGuideStep()

func testAdvanceGuideChordNavigatesWithinAndAcrossSteps() {
    let session = ImprovSession()
    session.newGuideSequence(title: "Chord Nav Test")
    do {
        // Step 0: 2 chords. Step 1: no chord progression at all (must be skipped through
        // entirely). Step 2: 2 chords.
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: ChordProgressionTemplate(name: "step0", degrees: ["I", "V"]))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"), chordProgression: ChordProgressionTemplate(name: "step2", degrees: ["I", "IV"]))
        try session.startGuide()

        check(session.currentGuideChordIndex, nil, "no chord selected right after starting the guide")

        session.advanceGuideChord(by: 1)
        check(session.currentGuideStepIndex, 0, "first right-press stays on step 0")
        check(session.currentGuideChordIndex, 0, "first right-press selects step 0's first chord, not a neighbor's")

        session.advanceGuideChord(by: 1)
        check(session.currentGuideStepIndex, 0, "second right-press stays on step 0")
        check(session.currentGuideChordIndex, 1, "second right-press selects step 0's second chord")

        session.advanceGuideChord(by: 1)
        check(session.currentGuideStepIndex, 2, "right-press past step 0's last chord skips the chord-less step 1 entirely")
        check(session.currentGuideChordIndex, 0, "...landing on step 2's first chord")

        session.advanceGuideChord(by: 1)
        check(session.currentGuideStepIndex, 2, "another right-press stays on step 2")
        check(session.currentGuideChordIndex, 1, "...selecting step 2's second (last) chord")

        session.advanceGuideChord(by: 1)
        check(session.currentGuideStepIndex, 2, "right-press at the sequence's very end is a no-op (step)")
        check(session.currentGuideChordIndex, 1, "right-press at the sequence's very end is a no-op (chord)")

        session.advanceGuideChord(by: -1)
        session.advanceGuideChord(by: -1)
        check(session.currentGuideStepIndex, 0, "left-presses skip the chord-less step 1 backward too")
        check(session.currentGuideChordIndex, 1, "...landing on step 0's LAST chord (not its first)")

        session.advanceGuideStep(by: 1)
        check(session.currentGuideChordIndex, nil, "advanceGuideStep (up/down) resets currentGuideChordIndex")
    } catch {
        failures += 1
        print("FAIL [advanceGuideChord]: threw \(error)")
    }
}
testAdvanceGuideChordNavigatesWithinAndAcrossSteps()

func testAdvanceGuideChordDoesNothingWhenGuideIsNotRunning() {
    let session = ImprovSession()
    session.newGuideSequence(title: "Not Running")
    do {
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: ChordProgressionTemplate(name: "s", degrees: ["I", "V"]))
        session.advanceGuideChord(by: 1)
        check(session.currentGuideChordIndex, nil, "advanceGuideChord is a no-op when the guide hasn't been started")
    } catch {
        failures += 1
        print("FAIL [advanceGuideChord not running]: threw \(error)")
    }
}
testAdvanceGuideChordDoesNothingWhenGuideIsNotRunning()

// MARK: - GuitarChordShapeTests (mirrors Tests/AppCoreTests/GuitarChordShapeTests.swift) —
// every covered shape's ACTUAL sounded pitch classes are recomputed here and compared
// against ChordVocabulary's own intervalsFromRoot, independent of the hand-verification that
// went into transcribing Sources/AppCore/GuitarChordShapes.swift in the first place — this
// is what would catch a future transcription slip (a wrong fret/finger number) even though
// the shape data itself is a fixed literal table, not something computed from theory.

/// Open strings' pitch classes, string 6 (low E) ... string 1 (high e).
private let openStringPitchClasses = [4, 9, 2, 7, 11, 4]

/// The set of pitch classes (relative to `root`, i.e. matching `ChordTemplate
/// .intervalsFromRoot`'s own convention) actually sounded by `diagram` — recomputed
/// independently of `GuitarChordShape` itself, from nothing but open-string tuning + fret
/// arithmetic, so this only agrees with the shape table if that table is really correct.
func soundedRelativePitchClasses(_ diagram: GuitarChordShape.Diagram, root: Int) -> Set<Int> {
    var result: Set<Int> = []
    for (index, position) in diagram.positions.enumerated() {
        guard let relativeFret = position.relativeFret else { continue }
        let fret = diagram.barreFret + relativeFret
        let sounded = (openStringPitchClasses[index] + fret) % 12
        result.insert(((sounded - root) % 12 + 12) % 12)
    }
    return result
}

func testGuitarChordShapesSoundTheRightIntervalsForEveryCoveredQuality() {
    let coveredTemplateIDs = ["Ma", "mi", "7", "Ma7", "mi7", "mi7b5", "dim7", "aug", "dim", "miMa7", "7#5", "7b5"]
    for templateID in coveredTemplateIDs {
        guard let template = ChordVocabulary.byID(templateID) else {
            failures += 1
            checks += 1
            print("FAIL [guitar chord shape \(templateID)]: no such ChordTemplate")
            continue
        }
        let expected = Set(template.intervalsFromRoot.map { (($0 % 12) + 12) % 12 })
        for root in [0, 5, 7, 11] { // F and G specifically double-check the well-known "F/G barre chord" fret positions
            guard let diagram = GuitarChordShape.diagram(forRoot: root, chordTemplateID: templateID) else {
                failures += 1
                checks += 1
                print("FAIL [guitar chord shape \(templateID) root \(root)]: diagram(forRoot:chordTemplateID:) returned nil for a supposedly-covered quality")
                continue
            }
            check(soundedRelativePitchClasses(diagram, root: root), expected, "guitar shape \(templateID) at root \(root) sounds exactly \(template.intervalsFromRoot)")
        }
    }
    // The two well-known reference positions from real guitar knowledge: F barre chord at
    // fret 1, G barre chord at fret 3 (both root-position major shapes).
    check(GuitarChordShape.diagram(forRoot: 5, chordTemplateID: "Ma")?.barreFret, 1, "F major barre chord sits at fret 1")
    check(GuitarChordShape.diagram(forRoot: 7, chordTemplateID: "Ma")?.barreFret, 3, "G major barre chord sits at fret 3")
}
testGuitarChordShapesSoundTheRightIntervalsForEveryCoveredQuality()

func testGuitarChordShapeReturnsNilForAnUncoveredQuality() {
    check(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "Ma7#5"), nil, "Ma7#5 has no verified standard shape, so diagram(forRoot:chordTemplateID:) returns nil")
    check(GuitarChordShape.diagram(forRoot: 0, chordTemplateID: "not-a-real-template"), nil, "unknown chordTemplateID also returns nil")
}
testGuitarChordShapeReturnsNilForAnUncoveredQuality()

func testVirtualKeyboardStateExposesCurrentStepChordProgression() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startVirtualKeyboard(port: 18411)
        let client = "&client=progression-client&name=Progressor"

        session.newGuideSequence(title: "Progression Test")
        // C Ionian + "ii-V-I (jazz)" resolves to Dmi, GMa, CMa (see `RomanNumeralChord` —
        // roman-numeral case IS the quality, taken literally as a plain triad; no 7ths):
        // exercises both the label formatting and the major/minor quality mapping.
        let progression = ChordProgressionTemplate(name: "ii-V-I (jazz)", degrees: ["ii", "V", "I"])
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: progression)
        try session.startGuide()
        Thread.sleep(forTimeInterval: 0.1)

        if let withProgression = syncGET("http://127.0.0.1:18411/state?dummy=1" + client) {
            check(withProgression.body.contains("\"currentChordProgressionName\":\"ii-V-I (jazz)\""), true, "guide state exposes the attached progression's name")
            check(withProgression.body.contains("\"label\":\"Dmi\""), true, "progression entry 0 (ii) resolves to Dmi")
            check(withProgression.body.contains("\"label\":\"GMa\""), true, "progression entry 1 (V) resolves to GMa")
            check(withProgression.body.contains("\"label\":\"CMa\""), true, "progression entry 2 (I) resolves to CMa")
            check(withProgression.body.contains("\"quality\":\"minor\""), true, "Dmi entry carries quality \"minor\" for wheel matching")
            check(withProgression.body.contains("\"quality\":\"major\""), true, "G7/CMa entries carry quality \"major\" for wheel matching")
        } else {
            failures += 1
            print("FAIL [virtual keyboard chord progression]: no response")
        }

        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [virtual keyboard chord progression]: threw \(error)")
    }
}
testVirtualKeyboardStateExposesCurrentStepChordProgression()

func testReleaseAllKeysClearsHeldPitchesForOneTrackOnly() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
    checks += 1
    do {
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.midiMerged)
        session.pressKey(pitch: 60, track: .computerKeyboard)
        session.pressKey(pitch: 64, track: .midiMerged)
        session.pressKey(pitch: 67, track: .midiMerged)
        session.releaseAllKeys(track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.heldPitches.isEmpty, true, "releaseAllKeys clears every held pitch on the targeted track")
        check(session.tracks.first { $0.id == .computerKeyboard }?.heldPitches, Set([60]), "releaseAllKeys leaves an unrelated track's held pitches untouched")
    } catch {
        failures += 1
        print("FAIL [releaseAllKeys]: threw \(error)")
    }
}
testReleaseAllKeysClearsHeldPitchesForOneTrackOnly()

func testRecordingCapturesFilteredTrackEvents() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.startTrack(.computerKeyboard)
        try session.startTrack(.microphone)
        try session.startRecording(title: "Test", tracks: [.computerKeyboard])
        session.pressKey(pitch: 60, track: .computerKeyboard) // should be captured
        session.pressKey(pitch: 64, track: .microphone) // filtered out, should not be captured
        Thread.sleep(forTimeInterval: 0.05)
        let soundTrack = try session.stopRecording()
        check(soundTrack.events.count, 1, "recording captures only the filtered track's events")
        check(soundTrack.events.first?.trackID, "clavier", "captured event carries the correct wire track id")
        check(soundTrack.events.first?.pitch, 60, "captured event carries the correct pitch")
    } catch {
        failures += 1
        print("FAIL [recording captures filtered track events]: threw \(error)")
    }
}
testRecordingCapturesFilteredTrackEvents()

func testStartRecordingTwiceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.startRecording(title: "A")
        do {
            try session.startRecording(title: "B")
            failures += 1
            print("FAIL [start recording twice throws]: did not throw")
        } catch ImprovSession.SessionError.alreadyRecording {
            // expected
        }
    } catch {
        failures += 1
        print("FAIL [start recording twice throws]: threw \(error)")
    }
}
testStartRecordingTwiceThrows()

func testStopRecordingWithoutStartingThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.stopRecording()
        failures += 1
        print("FAIL [stop recording without starting throws]: did not throw")
    } catch ImprovSession.SessionError.notRecording {
        // expected
    } catch {
        failures += 1
        print("FAIL [stop recording without starting throws]: wrong error \(error)")
    }
}
testStopRecordingWithoutStartingThrows()

func testSoundTrackSaveThenLoadRoundTrips() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.startRecording(title: "RoundTrip")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveSoundTrack(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadSoundTrack(fromJSONFile: tempFile.path)
        check(reloaded.currentSoundTrack?.events.count, session.currentSoundTrack?.events.count, "soundtrack round trips through JSON")
    } catch {
        failures += 1
        print("FAIL [soundtrack save/load round trip]: threw \(error)")
    }
}
testSoundTrackSaveThenLoadRoundTrips()

func testPlaySoundTrackTracksPlaybackStateThenClearsItWhenFinished() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        try session.startRecording(title: "Play")
        session.pressKey(pitch: 60)
        Thread.sleep(forTimeInterval: 0.05)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.playSoundTrack()
        check(session.isPlayingSoundTrack, true, "playSoundTrack sets isPlayingSoundTrack")

        Thread.sleep(forTimeInterval: (session.currentSoundTrack?.durationSeconds ?? 0) + 0.4)
        check(session.isPlayingSoundTrack, false, "soundtrack playback finished clears isPlayingSoundTrack")
        check(session.soundTrackHeldPitches, [], "soundtrack playback finished clears soundTrackHeldPitches")
    } catch {
        failures += 1
        print("FAIL [play soundtrack tracks playback state]: threw \(error)")
    }
}
testPlaySoundTrackTracksPlaybackStateThenClearsItWhenFinished()

func testPlaySoundTrackWithoutARecordingThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.playSoundTrack()
        failures += 1
        print("FAIL [play soundtrack without a recording throws]: did not throw")
    } catch ImprovSession.SessionError.noSoundTrackRecorded {
        // expected
    } catch {
        failures += 1
        print("FAIL [play soundtrack without a recording throws]: wrong error \(error)")
    }
}
testPlaySoundTrackWithoutARecordingThrows()

func testComposeSoundTrackToPiecesWithAFakeGeneratorProducesValidatedPieces() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path) // establishes pieceFolder for saving candidates

        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "From Recording", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1) { prompt, connection in
            if !prompt.contains("ON") { failures += 1; print("FAIL [compose soundtrack to pieces]: prompt doesn't mention the recorded events") }
            return fakeResponse
        }
        check(paths.count, 1, "composeSoundTrackToPieces saved exactly one candidate")
        check(session.piece?.title, "From Recording", "composeSoundTrackToPieces sets the current piece to the last candidate")
        check(FileManager.default.fileExists(atPath: paths[0]), true, "the candidate piece file was actually written")
    } catch {
        failures += 1
        print("FAIL [compose soundtrack to pieces]: threw \(error)")
    }
}
testComposeSoundTrackToPiecesWithAFakeGeneratorProducesValidatedPieces()

func testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        try session.listPieceFiles(in: folder.path)
        try session.startRecording(title: "ForCompose")
        session.pressKey(pitch: 62)
        session.releaseKey(pitch: 62)
        _ = try session.stopRecording()

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 90, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        let paths = try session.composeSoundTrackToPieces(candidateCount: 1, title: "My Own Title") { _, _ in fakeResponse }
        check(session.piece?.title, "My Own Title", "composeSoundTrackToPieces title override wins over the LLM's own title")
        checks += 1
        if !(paths.first?.hasSuffix("My Own Title.json") ?? false) {
            failures += 1
            print("FAIL [compose soundtrack title override filename]: \(paths)")
        }
    } catch {
        failures += 1
        print("FAIL [compose soundtrack to pieces with title override]: threw \(error)")
    }
}
testComposeSoundTrackToPiecesWithATitleOverridesTheLLMsOwnTitle()

func testCurrentTextCompositionPromptWithoutSourceTextOrOverrideThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.currentTextCompositionPrompt()
        failures += 1
        print("FAIL [currentTextCompositionPrompt without source text throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .noSourceText {
            failures += 1
            print("FAIL [currentTextCompositionPrompt without source text throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [currentTextCompositionPrompt without source text throws]: unexpected error \(error)")
    }
}
testCurrentTextCompositionPromptWithoutSourceTextOrOverrideThrows()

func testCurrentSoundTrackCompositionPromptWithoutARecordingOrOverrideThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        _ = try session.currentSoundTrackCompositionPrompt()
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if error != .noSoundTrackRecorded {
            failures += 1
            print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt without recording throws]: unexpected error \(error)")
    }
}
testCurrentSoundTrackCompositionPromptWithoutARecordingOrOverrideThrows()

func testSetPromptsFolderCreatesAllFiveSubfoldersAndListsFiles() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)

        var isDirectory: ObjCBool = false
        for subfolder in ["Cadrage Composition Descriptive", "Cadrage Composition Soundtrack", "composition Descriptive", "Indications Soundtracks", "Export"] {
            checks += 1
            if !FileManager.default.fileExists(atPath: root.appendingPathComponent(subfolder).path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                failures += 1
                print("FAIL [setPromptsFolder creates \(subfolder) subfolder]")
            }
        }
        check(session.textFramingFiles, [], "setPromptsFolder starts with no text framing files")
        check(session.soundTrackFramingFiles, [], "setPromptsFolder starts with no soundtrack framing files")
        check(session.soundTrackInstructionsFiles, [], "setPromptsFolder starts with no soundtrack instructions files")
        check(session.compositionFolder, root.appendingPathComponent("composition Descriptive").path, "setPromptsFolder derives compositionFolder")
        check(session.compositionFiles, [], "setPromptsFolder starts with no composition description files")
    } catch {
        failures += 1
        print("FAIL [setPromptsFolder creates subfolders and lists files]: threw \(error)")
    }
}
testSetPromptsFolderCreatesAllFiveSubfoldersAndListsFiles()

func testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSourceText("a poem about the sea")

        try session.exportTextCompositionPrompt(as: "my-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-export.txt"), encoding: .utf8)
        check(exported, try session.currentTextCompositionPrompt(), "exported file matches currentTextCompositionPrompt()")
        checks += 1
        if !exported.contains("a poem about the sea") {
            failures += 1
            print("FAIL [exportTextCompositionPrompt]: exported text missing source text")
        }
    } catch {
        failures += 1
        print("FAIL [exportTextCompositionPrompt writes to Export subfolder]: threw \(error)")
    }
}
testExportTextCompositionPromptWritesCurrentPromptToExportSubfolder()

func testExportSoundTrackCompositionPromptWritesCurrentPromptToExportSubfolder() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        try session.startRecording(title: "ForExport")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        try session.exportSoundTrackCompositionPrompt(as: "my-soundtrack-export")
        let exported = try String(contentsOf: root.appendingPathComponent("Export/my-soundtrack-export.txt"), encoding: .utf8)
        check(exported, try session.currentSoundTrackCompositionPrompt(), "exported file matches currentSoundTrackCompositionPrompt()")
    } catch {
        failures += 1
        print("FAIL [exportSoundTrackCompositionPrompt writes to Export subfolder]: threw \(error)")
    }
}
testExportSoundTrackCompositionPromptWritesCurrentPromptToExportSubfolder()

func testSaveAndUseSoundTrackCompositionInstructionsRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checkNil(session.currentSoundTrackCompositionInstructions(), "no instructions set initially")

        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        try session.saveSoundTrackCompositionInstructions(as: "my-instructions")
        check(session.soundTrackInstructionsFiles, ["my-instructions.txt"], "saveSoundTrackCompositionInstructions adds the file")

        session.resetSoundTrackCompositionInstructions()
        checkNil(session.currentSoundTrackCompositionInstructions(), "reset clears instructions")

        try session.useSoundTrackCompositionInstructions(atIndex: 0)
        check(session.activeSoundTrackCompositionInstructions, "romantique, mode mineur", "useSoundTrackCompositionInstructions reloads the saved value")
    } catch {
        failures += 1
        print("FAIL [save and use soundtrack composition instructions round trips]: threw \(error)")
    }
}
testSaveAndUseSoundTrackCompositionInstructionsRoundTrips()

func testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.saveSoundTrackCompositionInstructions(as: "nothing-to-save")
            failures += 1
            print("FAIL [saveSoundTrackCompositionInstructions without any set throws]: did not throw")
        } catch ImprovSession.SessionError.noSoundTrackCompositionInstructions {
            // expected
        } catch {
            failures += 1
            print("FAIL [saveSoundTrackCompositionInstructions without any set throws]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [save soundtrack composition instructions without any set]: threw \(error)")
    }
}
testSaveSoundTrackCompositionInstructionsWithoutAnySetThrows()

func testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.useSoundTrackCompositionInstructions(atIndex: 0)
            failures += 1
            print("FAIL [useSoundTrackCompositionInstructions invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidSoundTrackInstructionsIndex {
                failures += 1
                print("FAIL [useSoundTrackCompositionInstructions invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [use soundtrack composition instructions with invalid index]: threw \(error)")
    }
}
testUseSoundTrackCompositionInstructionsWithInvalidIndexThrows()

func testCurrentSoundTrackCompositionPromptIncludesActiveInstructions() {
    do {
        let session = ImprovSession()
        try session.startRecording(title: "ForInstructions")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()
        session.setSoundTrackCompositionInstructions("romantique, mode mineur")
        let prompt = try session.currentSoundTrackCompositionPrompt()
        checks += 1
        if !prompt.contains("romantique, mode mineur") {
            failures += 1
            print("FAIL [currentSoundTrackCompositionPrompt includes active instructions]")
        }
    } catch {
        failures += 1
        print("FAIL [currentSoundTrackCompositionPrompt includes active instructions]: threw \(error)")
    }
}
testCurrentSoundTrackCompositionPromptIncludesActiveInstructions()

// Mirrors ImprovSessionTests.swift's framing-sentence tests.
func testCurrentFramingSentenceDefaultsToTheBuiltInConstants() {
    let session = ImprovSession()
    check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "text framing defaults to the built-in constant")
    check(session.currentSoundTrackFramingSentence(), LLMPieceComposer.defaultSoundTrackFramingSentence, "soundtrack framing defaults to the built-in constant")
}
testCurrentFramingSentenceDefaultsToTheBuiltInConstants()

func testSetTextFramingSentenceIsReflectedInTheFullPrompt() {
    do {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setTextFramingSentence("Custom framing sentence.")
        check(session.currentTextFramingSentence(), "Custom framing sentence.", "setTextFramingSentence updates currentTextFramingSentence")
        checks += 1
        if !(try session.currentTextCompositionPrompt()).contains("Custom framing sentence.") {
            failures += 1
            print("FAIL [setTextFramingSentence reflected in full prompt]")
        }
    } catch {
        failures += 1
        print("FAIL [setTextFramingSentence reflected in full prompt]: threw \(error)")
    }
}
testSetTextFramingSentenceIsReflectedInTheFullPrompt()

func testSetTextFramingSentenceEmptyStringRevertsToDefault() {
    let session = ImprovSession()
    session.setTextFramingSentence("Custom.")
    check(session.currentTextFramingSentence(), "Custom.", "setTextFramingSentence sets a custom value")
    session.setTextFramingSentence("")
    check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "empty setTextFramingSentence reverts to default")
}
testSetTextFramingSentenceEmptyStringRevertsToDefault()

func testSaveAndUseTextFramingSentenceRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setTextFramingSentence("A distinctive custom framing sentence.")

        try session.saveTextFramingSentence(as: "my-framing")
        check(session.textFramingFiles, ["my-framing.txt"], "saveTextFramingSentence adds the file to textFramingFiles")

        session.resetTextFramingSentence()
        check(session.currentTextFramingSentence(), LLMPieceComposer.defaultTextFramingSentence, "resetTextFramingSentence reverts to default")

        try session.useTextFramingSentence(atIndex: 0)
        check(session.activeTextFramingSentence, "A distinctive custom framing sentence.", "useTextFramingSentence reloads the saved sentence")
    } catch {
        failures += 1
        print("FAIL [save and use text framing sentence round trips]: threw \(error)")
    }
}
testSaveAndUseTextFramingSentenceRoundTrips()

func testSaveAndUseSoundTrackFramingSentenceRoundTrips() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        session.setSoundTrackFramingSentence("A distinctive soundtrack framing sentence.")

        try session.saveSoundTrackFramingSentence(as: "my-soundtrack-framing")
        check(session.soundTrackFramingFiles, ["my-soundtrack-framing.txt"], "saveSoundTrackFramingSentence adds the file to soundTrackFramingFiles")

        session.resetSoundTrackFramingSentence()
        try session.useSoundTrackFramingSentence(named: "my-soundtrack-framing.txt")
        check(session.activeSoundTrackFramingSentence, "A distinctive soundtrack framing sentence.", "useSoundTrackFramingSentence reloads the saved sentence")
    } catch {
        failures += 1
        print("FAIL [save and use soundtrack framing sentence round trips]: threw \(error)")
    }
}
testSaveAndUseSoundTrackFramingSentenceRoundTrips()

func testUseTextFramingSentenceWithInvalidIndexThrows() {
    do {
        let session = ImprovSession()
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try session.setPromptsFolder(root.path)
        checks += 1
        do {
            try session.useTextFramingSentence(atIndex: 0)
            failures += 1
            print("FAIL [useTextFramingSentence invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidTextFramingIndex {
                failures += 1
                print("FAIL [useTextFramingSentence invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [use text framing sentence with invalid index]: threw \(error)")
    }
}
testUseTextFramingSentenceWithInvalidIndexThrows()

// Mirrors ImprovSessionTests.swift's composition-description tests.
func testSaveThenLoadCompositionDescriptionRoundTrips() {
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)

        session.setCompositionTitle("My Ballad")
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.saveCompositionDescription(as: "my-description")
        check(session.compositionFiles, ["my-description.json"], "saveCompositionDescription adds the file to compositionFiles")

        let reloaded = ImprovSession()
        try reloaded.listCompositionFiles(in: folder.path)
        try reloaded.loadCompositionDescription(atIndex: 0)
        check(reloaded.compositionTitle, "My Ballad", "loadCompositionDescription restores the title")
        check(reloaded.sourceText, "a poem about the sea", "loadCompositionDescription restores the source text")
        check(reloaded.additionalCompositionInstructions, "romantique, mode mineur", "loadCompositionDescription restores the indications")
    } catch {
        failures += 1
        print("FAIL [save then load composition description round trips]: threw \(error)")
    }
}
testSaveThenLoadCompositionDescriptionRoundTrips()

func testLoadCompositionDescriptionAtInvalidIndexThrows() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let session = ImprovSession()
        try session.listCompositionFiles(in: folder.path)
        checks += 1
        do {
            try session.loadCompositionDescription(atIndex: 0)
            failures += 1
            print("FAIL [loadCompositionDescription invalid index throws]: did not throw")
        } catch let error as ImprovSession.SessionError {
            if error != .invalidCompositionIndex {
                failures += 1
                print("FAIL [loadCompositionDescription invalid index throws]: wrong error \(error)")
            }
        }
    } catch {
        failures += 1
        print("FAIL [load composition description at invalid index]: threw \(error)")
    }
}
testLoadCompositionDescriptionAtInvalidIndexThrows()

func testSaveCompositionDescriptionWithoutSourceTextThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.saveCompositionDescription(as: "/tmp/whatever")
        failures += 1
        print("FAIL [saveCompositionDescription without sourceText throws]: did not throw")
    } catch ImprovSession.SessionError.noSourceText {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without sourceText throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutSourceTextThrows()

func testSaveCompositionDescriptionWithoutFolderListedThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.saveCompositionDescription(as: "bare-name")
        failures += 1
        print("FAIL [saveCompositionDescription without folder listed throws]: did not throw")
    } catch ImprovSession.SessionError.noCompositionFolderListed {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without folder listed throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutFolderListedThrows()

func testSaveCompositionDescriptionWithoutHavingSavedOnceThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.saveCompositionDescription()
        failures += 1
        print("FAIL [saveCompositionDescription without prior save throws]: did not throw")
    } catch ImprovSession.SessionError.noCurrentCompositionFile {
        // expected
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription without prior save throws]: wrong error \(error)")
    }
}
testSaveCompositionDescriptionWithoutHavingSavedOnceThrows()

func testSaveCompositionDescriptionReSavesToTheSameFile() {
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try session.listCompositionFiles(in: folder.path)
        session.setSourceText("first version")
        try session.saveCompositionDescription(as: "iterate")

        session.setSourceText("second version")
        try session.saveCompositionDescription()

        let reloaded = ImprovSession()
        try reloaded.loadCompositionDescription(fromJSONFile: folder.appendingPathComponent("iterate.json").path)
        check(reloaded.sourceText, "second version", "saveCompositionDescription() re-saves to the same file")
    } catch {
        failures += 1
        print("FAIL [saveCompositionDescription re-saves to the same file]: threw \(error)")
    }
}
testSaveCompositionDescriptionReSavesToTheSameFile()

func testSaveThenLoadRoundTripsThePieceThroughJSON() {
    let session = ImprovSession()
    session.loadDemoPiece()
    let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
    defer { try? FileManager.default.removeItem(at: tempFile) }
    do {
        try session.savePiece(toJSONFile: tempFile.path)
        let reloadedSession = ImprovSession()
        try reloadedSession.loadPiece(fromJSONFile: tempFile.path)
        check(reloadedSession.piece, session.piece, "improv session save/load round trips through JSON")
    } catch {
        checks += 1
        failures += 1
        print("FAIL [improv session save/load round trip]: threw \(error)")
    }
}

func testLoadingAMissingFileThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.loadPiece(fromJSONFile: "/no/such/file.json")
        failures += 1
        print("FAIL [improv session load missing file throws]: did not throw")
    } catch {
        // expected
    }
}

func testListPieceFilesFindsJSONFilesAndIgnoresOthers() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try Data().write(to: folder.appendingPathComponent("b.json"))
        try Data().write(to: folder.appendingPathComponent("a.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        if session.pieceFiles != ["a.json", "b.json"] {
            failures += 1
            print("FAIL [list piece files finds json, ignores others]: \(session.pieceFiles)")
        }
    } catch {
        failures += 1
        print("FAIL [list piece files finds json, ignores others]: threw \(error)")
    }
}

func testUsePieceByIndexAndNameLoadFromTheListedFolder() {
    checks += 2
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let writer = ImprovSession()
        writer.loadDemoPiece()
        try writer.savePiece(toJSONFile: folder.appendingPathComponent("demo.json").path)

        let session = ImprovSession()
        try session.listPieceFiles(in: folder.path)
        try session.loadPiece(atIndex: 0)
        if session.piece?.title != "ii-V-I demo" {
            failures += 1
            print("FAIL [use-piece by index]: \(String(describing: session.piece?.title))")
        }

        let byName = ImprovSession()
        try byName.listPieceFiles(in: folder.path)
        try byName.loadPiece(named: "demo.json")
        if byName.piece?.title != "ii-V-I demo" {
            failures += 1
            print("FAIL [use-piece by name]: \(String(describing: byName.piece?.title))")
        }
    } catch {
        failures += 2
        print("FAIL [use-piece by index/name]: threw \(error)")
    }
}

func testSaveWithoutEverLoadingOrSavingThrows() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.savePiece()
        failures += 1
        print("FAIL [bare save without a current file throws]: did not throw")
    } catch {
        // expected
    }
}

func testSaveAsThenBareSaveRoundTripToTheSameFile() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }

        let session = ImprovSession()
        session.loadDemoPiece()
        try session.listPieceFiles(in: folder.path)
        try session.savePiece(as: "my-piece")

        let expectedPath = folder.appendingPathComponent("my-piece.json").path
        if session.currentPieceFilePath != expectedPath || !FileManager.default.fileExists(atPath: expectedPath) {
            failures += 1
            print("FAIL [save-as then bare save]: currentPieceFilePath=\(String(describing: session.currentPieceFilePath))")
        }
        try session.savePiece() // re-save to the same resolved path, should not throw
    } catch {
        failures += 1
        print("FAIL [save-as then bare save]: threw \(error)")
    }
}

func testSaveAsWithoutAPieceFolderListedThrowsForABareName() {
    let session = ImprovSession()
    session.loadDemoPiece()
    checks += 1
    do {
        try session.savePiece(as: "my-piece")
        failures += 1
        print("FAIL [save-as bare name without folder throws]: did not throw")
    } catch {
        // expected
    }
}

// MARK: - GuideSequence / ImprovSession guide-mode tests

func testNewGuideSequenceThenAddStepsThenStartAndAdvance() {
    do {
        let session = ImprovSession()
        checkNil(session.currentGuide, "improv session starts with no guide sequence")
        session.newGuideSequence(title: "Practice")
        check(session.currentGuide?.title, "Practice", "newGuideSequence sets title")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 2, scaleID: "dorian"))
        check(session.currentGuide?.steps.count, 2, "addGuideStep appends steps")

        checkNil(session.currentGuideStepIndex, "guide not started has no current step index")
        checkNil(session.currentGuideStepMode(), "guide not started has no current mode")

        try session.startGuide()
        check(session.currentGuideStepIndex, 0, "startGuide defaults to step 0")
        check(session.currentGuideStepMode()?.displayName, "C Major", "guide step 0 mode")

        session.advanceGuideStep(by: 1)
        check(session.currentGuideStepIndex, 1, "advanceGuideStep(+1) moves to step 1")
        check(session.currentGuideStepMode()?.displayName, "D Dorian", "guide step 1 mode")

        session.advanceGuideStep(by: 1)
        check(session.currentGuideStepIndex, 1, "advanceGuideStep clamps at the last step")

        session.advanceGuideStep(by: -5)
        check(session.currentGuideStepIndex, 0, "advanceGuideStep clamps at the first step")

        session.stopGuide()
        checkNil(session.currentGuideStepIndex, "stopGuide clears the current step index")
    } catch {
        failures += 1
        print("FAIL [guide sequence start/advance]: threw \(error)")
    }
}

func testAddGuideStepWithoutASequenceThrows() {
    let session = ImprovSession()
    checks += 1
    do {
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        failures += 1
        print("FAIL [addGuideStep without sequence throws]: did not throw")
    } catch {
        // expected
    }
}

func testAddGuideStepWithUnknownScaleIDThrowsAndDoesNotAppendAStep() {
    let session = ImprovSession()
    session.newGuideSequence(title: "Practice")
    checks += 1
    do {
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "majeur")) // not a real ScaleLibrary id
        failures += 1
        print("FAIL [addGuideStep unknown scaleID throws]: did not throw")
    } catch {
        // expected
    }
    check(session.currentGuide?.steps.count, 0, "addGuideStep with an unresolvable reference doesn't leave a dangling step")
}

func testTrackIDWireIDTextRoundTrips() {
    for id: TrackID in [.midiMerged, .computerKeyboard, .webKeyboard(clientID: "abc-123"), .microphone, .midiSource(0), .midiSource(3)] {
        guard let wireText = id.wireIDText else {
            failures += 1; checks += 1
            print("FAIL [TrackID wireIDText round trip]: \(id) has no wireIDText")
            continue
        }
        check(TrackID(wireIDText: wireText), id, "TrackID(wireIDText:) inverts wireIDText for \(id)")
    }
    checkNil(TrackID(wireIDText: "not-a-real-id"), "TrackID(wireIDText:) rejects an unrecognized string")
}

func testSceneSaveAndLoadRoundTripsTrackListeningAndSound() {
    do {
        let session = ImprovSession()
        try session.start()
        try session.startTrack(.computerKeyboard)
        try session.setSoundEnabled(true, for: .computerKeyboard)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Test Scene", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        let before = reloaded.tracks.first { $0.id == .computerKeyboard }
        check(before?.isListening, false, "fresh session's computer-keyboard track starts not listening")

        try reloaded.loadScene(fromJSONFile: tempFile.path)
        let after = reloaded.tracks.first { $0.id == .computerKeyboard }
        check(after?.isListening, true, "loadScene restores isListening")
        check(after?.soundEnabled, true, "loadScene restores soundEnabled")
    } catch {
        failures += 1
        print("FAIL [scene save/load round trip]: threw \(error)")
    }
}

func testLoadSceneLeavesTracksNotMentionedUntouched() {
    do {
        let session = ImprovSession()
        try session.start()
        // An explicitly empty scene (built by hand, not via `saveScene` — which always
        // captures every local track, including as "not listening") must not touch
        // whatever's currently listening: only tracks it actually mentions are restored.
        let emptyScene = Scene(title: "Empty", roles: [])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(emptyScene).write(to: tempFile)

        try session.startTrack(.computerKeyboard)
        try session.loadScene(fromJSONFile: tempFile.path)
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "loading a scene that doesn't mention a track leaves it untouched")
    } catch {
        failures += 1
        print("FAIL [scene leaves unmentioned tracks untouched]: threw \(error)")
    }
}

// MARK: - Scene roles — mirrors Tests/AppCoreTests/ImprovSessionTests.swift's tests of the same name.

func testNewSceneCreatesEmptyActiveScene() {
    let session = ImprovSession()
    checkNil(session.currentScene, "fresh session has no active scene")
    session.newScene(title: "Repetition")
    check(session.currentScene?.title, "Repetition", "newScene sets title")
    check(session.currentScene?.roles.count, 0, "newScene starts with no roles")
}

func testAddSceneRoleAppendsAndRemoveSceneRoleRemoves() {
    do {
        let session = ImprovSession()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano 1")
        check(session.currentScene?.roles.count, 1, "addSceneRole appends a role")
        check(session.currentScene?.roles.first?.name, "Piano 1", "addSceneRole sets the role's name")

        try session.removeSceneRole(roleID)
        check(session.currentScene?.roles.count, 0, "removeSceneRole removes the role")
    } catch {
        failures += 1
        print("FAIL [scene role add/remove]: threw \(error)")
    }
}

func testAddSceneRoleWithoutActiveSceneThrows() {
    let session = ImprovSession()
    do {
        _ = try session.addSceneRole(name: "Piano 1")
        failures += 1; checks += 1
        print("FAIL [addSceneRole without active scene throws]: did not throw")
    } catch {
        checks += 1 // expected
    }
}

func testAttachInstrumentAppliesRoleConfigurationAndAutoDetachesFromPreviousRole() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        let bassID = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)

        try session.attachInstrument(.computerKeyboard, toRole: pianoID)
        check(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID, .computerKeyboard, "attachInstrument sets attachedTrackID")
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "attachInstrument starts the track per the role's own isListening")

        // Moving the SAME instrument to a different role must auto-detach it from the first,
        // not throw/reject — the actual regression this choke point exists to prevent.
        try session.attachInstrument(.computerKeyboard, toRole: bassID)
        checkNil(session.currentScene?.roles.first { $0.id == pianoID }?.attachedTrackID, "attachInstrument auto-detaches from the previous role")
        check(session.currentScene?.roles.first { $0.id == bassID }?.attachedTrackID, .computerKeyboard, "attachInstrument attaches to the new role")
    } catch {
        failures += 1
        print("FAIL [attachInstrument auto-detach]: threw \(error)")
    }
}

func testDetachInstrumentClearsAttachmentWithoutStoppingTrack() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")
        try session.setSceneRoleListening(roleID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: roleID)
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "instrument listening after attach")

        try session.detachInstrument(fromRole: roleID)
        checkNil(session.currentScene?.roles.first { $0.id == roleID }?.attachedTrackID, "detachInstrument clears the attachment")
        // Detaching is bookkeeping only — the instrument itself keeps listening, mirroring
        // `stopTrack`'s own "state survives a stop" convention.
        check(session.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "detachInstrument doesn't stop the track")
    } catch {
        failures += 1
        print("FAIL [detachInstrument bookkeeping-only]: threw \(error)")
    }
}

func testAttachInstrumentThrowsForUnknownRoleOrTrack() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let roleID = try session.addSceneRole(name: "Piano")

        do {
            try session.attachInstrument(.computerKeyboard, toRole: UUID())
            failures += 1; checks += 1
            print("FAIL [attachInstrument unknown role throws]: did not throw")
        } catch {
            checks += 1 // expected
        }
        do {
            try session.attachInstrument(.midiSource(99), toRole: roleID)
            failures += 1; checks += 1
            print("FAIL [attachInstrument unknown track throws]: did not throw")
        } catch {
            checks += 1 // expected
        }
    } catch {
        failures += 1
        print("FAIL [attachInstrument error paths]: threw \(error)")
    }
}

func testFreeSceneRolesAndUnassignedInstruments() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Test")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        check(session.freeSceneRoles().map(\.name), ["Basse"], "freeSceneRoles lists only unattached roles")
        check(session.unassignedInstruments().contains { $0.id == .computerKeyboard }, false, "attached instrument is not unassigned")
        check(session.unassignedInstruments().contains { $0.id == .microphone }, true, "never-attached instrument is unassigned")
    } catch {
        failures += 1
        print("FAIL [freeSceneRoles/unassignedInstruments]: threw \(error)")
    }
}

func testSceneSaveLoadRoundTripReattachesComputerKeyboardAndReportsFreeRoles() {
    do {
        let session = ImprovSession()
        try session.start()
        session.newScene(title: "Repetition")
        let pianoID = try session.addSceneRole(name: "Piano")
        _ = try session.addSceneRole(name: "Basse")
        try session.setSceneRoleListening(pianoID, isListening: true)
        try session.attachInstrument(.computerKeyboard, toRole: pianoID)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveScene(title: "Repetition", toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.start()
        try reloaded.loadScene(fromJSONFile: tempFile.path)

        check(reloaded.currentScene?.roles.count, 2, "loadScene restores both roles")
        let reloadedPiano = reloaded.currentScene?.roles.first { $0.name == "Piano" }
        check(reloadedPiano?.attachedTrackID, .computerKeyboard, "loadScene reattaches the computer keyboard automatically")
        check(reloaded.tracks.first { $0.id == .computerKeyboard }?.isListening, true, "loadScene applies the role's isListening")
        let reloadedBasse = reloaded.currentScene?.roles.first { $0.name == "Basse" }
        checkNil(reloadedBasse?.attachedTrackID, "an unattached role stays free after loadScene")
        // The direct fix for the reported bug: a role that couldn't reattach is reported, not
        // silently dropped.
        check(reloaded.log.contains { $0.contains("Basse") && $0.contains("libre") }, true, "loadScene logs which roles stayed free")
    } catch {
        failures += 1
        print("FAIL [scene save/load round trip with roles]: threw \(error)")
    }
}

func testLoadSceneMigratesLegacyFlatTrackFormat() {
    do {
        let legacyJSON = """
        {"title": "Ancienne Scene", "tracks": [
            {"trackID": "clavier", "isListening": true, "soundEnabled": true, "instrumentName": "mcb.sf2"}
        ]}
        """
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try legacyJSON.write(to: tempFile, atomically: true, encoding: .utf8)

        let session = ImprovSession()
        try session.start()
        try session.loadScene(fromJSONFile: tempFile.path)

        check(session.currentScene?.title, "Ancienne Scene", "legacy scene title migrates")
        check(session.currentScene?.roles.count, 1, "legacy scene produces one role per saved track")
        let role = session.currentScene?.roles.first
        check(role?.name, "Clavier ordinateur", "legacy track auto-named from its wire id")
        check(role?.attachedTrackID, .computerKeyboard, "legacy role reattaches to the computer keyboard")
        check(role?.lastAttachedInstrument, .computerKeyboard, "legacy role gets a computerKeyboard identity hint")
    } catch {
        failures += 1
        print("FAIL [loadScene migrates legacy format]: threw \(error)")
    }
}

func testLoadSceneDoesNotReattachMidiMergedHintInIndividualMode() {
    do {
        // `.midiMerged` has no CoreMIDI dependency (a singleton, unlike `.midiSource`), so this
        // is the one `matches(_:_:)` case fully testable without real hardware — see
        // `ImprovSession.matches(_:_:)`'s own doc comment for why `.midiPort` matching isn't
        // covered here (it needs a real or injectable CoreMIDI source list this test suite has
        // no way to control).
        let scene = Scene(title: "Old Setup", roles: [
            SceneRole(name: "Synth", lastAttachedInstrument: .midiMerged),
        ])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(scene).write(to: tempFile)

        let session = ImprovSession()
        try session.start()
        session.setMIDIFusionMode(.individual) // no MIDI hardware here, so this yields zero midi tracks
        try session.loadScene(fromJSONFile: tempFile.path)

        checkNil(session.currentScene?.roles.first?.attachedTrackID, "a .midiMerged hint doesn't reattach while in individual mode")
    } catch {
        failures += 1
        print("FAIL [loadScene midiMerged mode gate]: threw \(error)")
    }
}

testNewSceneCreatesEmptyActiveScene()
testAddSceneRoleAppendsAndRemoveSceneRoleRemoves()
testAddSceneRoleWithoutActiveSceneThrows()
testAttachInstrumentAppliesRoleConfigurationAndAutoDetachesFromPreviousRole()
testDetachInstrumentClearsAttachmentWithoutStoppingTrack()
testAttachInstrumentThrowsForUnknownRoleOrTrack()
testFreeSceneRolesAndUnassignedInstruments()
testSceneSaveLoadRoundTripReattachesComputerKeyboardAndReportsFreeRoles()
testLoadSceneMigratesLegacyFlatTrackFormat()
testLoadSceneDoesNotReattachMidiMergedHintInIndividualMode()

func testColorPaletteFileRoundTrips() {
    let file = ColorPaletteFile(palettes: ColorPalette.builtInDefaults)
    do {
        let data = try JSONEncoder().encode(file)
        let decoded = try JSONDecoder().decode(ColorPaletteFile.self, from: data)
        check(decoded.palettes, ColorPalette.builtInDefaults, "ColorPaletteFile round-trips through JSON unchanged")
    } catch {
        failures += 1
        print("FAIL [ColorPaletteFile round trip]: threw \(error)")
    }
}
testColorPaletteFileRoundTrips()

func testBuiltInDefaultPalettesAreThreeDistinctFullPalettes() {
    check(ColorPalette.builtInDefaults.count, 3, "builtInDefaults has 3 palettes")
    check(Set(ColorPalette.builtInDefaults.map(\.name)).count, 3, "builtInDefaults palette names are distinct")
    for palette in ColorPalette.builtInDefaults {
        check(palette.colors.count, 12, "\(palette.name) has 12 colors")
        check(Set(palette.colors).count, 12, "\(palette.name)'s 12 colors are distinct")
        check(palette.textColors.count, 12, "\(palette.name) has 12 text colors")
        for textColor in palette.textColors {
            check(textColor == "#ffffff" || textColor == "#111111", true, "\(palette.name)'s text colors are all either white or black")
        }
    }
}
testBuiltInDefaultPalettesAreThreeDistinctFullPalettes()

// The user hand-specified this exact pattern (white for every note except A/E/B, which get
// black) — not something `legibleTextColors(for:)` is expected to reproduce on its own, so
// this is pinned literally rather than re-derived from `PitchClassPalette.hex`.
func testDefaultPaletteTextColorsMatchHandSpecifiedPattern() {
    let palette = ColorPalette.builtInDefaults[0]
    check(palette.name, "Default", "builtInDefaults[0] is Default")
    // index: 0=C 1=Db 2=D 3=Eb 4=E 5=F 6=F# 7=G 8=Ab 9=A 10=Bb 11=B
    let expected = [
        "#ffffff", "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff",
        "#ffffff", "#ffffff", "#ffffff", "#111111", "#ffffff", "#111111",
    ]
    check(palette.textColors, expected, "Default's text colors are white except A(9)/E(4)/B(11), which are black")
}
testDefaultPaletteTextColorsMatchHandSpecifiedPattern()

func testLegibleTextColorsUsesYIQBrightnessThreshold() {
    let textColors = ColorPalette.legibleTextColors(for: ["#ffffff", "#000000", "#ffe119"])
    check(textColors, ["#111111", "#ffffff", "#111111"], "legibleTextColors picks black for bright colors, white for dark ones")
}
testLegibleTextColorsUsesYIQBrightnessThreshold()

func testSessionStartsWithDefaultPaletteMatchingPitchClassPalette() {
    let session = ImprovSession()
    check(session.colorPalettes.count, 1, "a fresh session starts with exactly one (fallback) palette")
    check(session.activeColorPalette.name, "Default", "the fallback palette is named Default")
    check(session.activeColorPalette.colors, PitchClassPalette.hex, "the fallback palette's colors mirror PitchClassPalette.hex")
}
testSessionStartsWithDefaultPaletteMatchingPitchClassPalette()

func testLoadOrCreateColorPalettesWritesBuiltInDefaultsOnFirstRunThenLoadsThem() {
    do {
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        check(FileManager.default.fileExists(atPath: tempFile.path), false, "the file doesn't exist yet")

        let session = ImprovSession()
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        check(FileManager.default.fileExists(atPath: tempFile.path), true, "loadOrCreateColorPalettes creates the file")
        check(session.colorPalettes, ColorPalette.builtInDefaults, "loadOrCreateColorPalettes loads the freshly-written built-in defaults")
        check(session.activeColorPalette.name, "Default", "the first palette in the file is active after loading")

        // A second session pointed at the SAME (now-existing) file must not overwrite it —
        // only ever create it once.
        try session.selectColorPalette(named: "Pastel")
        let reloaded = ImprovSession()
        try reloaded.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)
        check(reloaded.colorPalettes, ColorPalette.builtInDefaults, "loadOrCreateColorPalettes doesn't overwrite an existing file")
    } catch {
        failures += 1
        print("FAIL [loadOrCreateColorPalettes]: threw \(error)")
    }
}
testLoadOrCreateColorPalettesWritesBuiltInDefaultsOnFirstRunThenLoadsThem()

func testSelectColorPaletteByNameAndIndexAndRejectsInvalid() {
    do {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

        try session.selectColorPalette(named: "Contraste")
        check(session.activeColorPalette.name, "Contraste", "selectColorPalette(named:) switches the active palette")

        try session.selectColorPalette(atIndex: 2)
        check(session.activeColorPalette.name, "Pastel", "selectColorPalette(atIndex:) switches the active palette (0-based)")

        do {
            try session.selectColorPalette(named: "Not A Real Palette")
            failures += 1
            print("FAIL [selectColorPalette invalid name]: did not throw")
        } catch ImprovSession.SessionError.invalidColorPaletteIndex {
            // expected
        } catch {
            failures += 1
            print("FAIL [selectColorPalette invalid name]: wrong error \(error)")
        }

        do {
            try session.selectColorPalette(atIndex: 99)
            failures += 1
            print("FAIL [selectColorPalette invalid index]: did not throw")
        } catch ImprovSession.SessionError.invalidColorPaletteIndex {
            // expected
        } catch {
            failures += 1
            print("FAIL [selectColorPalette invalid index]: wrong error \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [selectColorPalette]: setup threw \(error)")
    }
}
testSelectColorPaletteByNameAndIndexAndRejectsInvalid()

func testLoadColorPalettesThrowsOnEmptyPalettesFile() {
    do {
        let session = ImprovSession()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try JSONEncoder().encode(ColorPaletteFile(palettes: [])).write(to: tempFile)
        do {
            try session.loadColorPalettes(fromJSONFile: tempFile.path)
            failures += 1
            print("FAIL [loadColorPalettes empty file]: did not throw")
        } catch ImprovSession.SessionError.emptyColorPaletteFile {
            // expected
        } catch {
            failures += 1
            print("FAIL [loadColorPalettes empty file]: wrong error \(error)")
        }
        // And the previous (fallback) palette must still be there — a failed load shouldn't
        // have cleared anything.
        check(session.colorPalettes.count, 1, "a failed load leaves the existing palettes untouched")
    } catch {
        failures += 1
        print("FAIL [loadColorPalettes empty file]: setup threw \(error)")
    }
}
testLoadColorPalettesThrowsOnEmptyPalettesFile()

// Real HTTP round trip: the active palette's colors must appear in BOTH the web console's
// and the virtual keyboard's `/state`, and switching palettes must be reflected on the very
// next poll — no page reload, no server restart.
func testActiveColorPaletteIsReflectedInWebConsoleAndVirtualKeyboardState() {
    checks += 1
    do {
        let session = ImprovSession()
        try session.start()
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadOrCreateColorPalettes(fromJSONFile: tempFile.path)

        try session.startWebConsole(port: 18400)
        try session.startVirtualKeyboard(port: 18401)
        Thread.sleep(forTimeInterval: 0.3)

        if let consoleState = syncGET("http://127.0.0.1:18400/state") {
            check(consoleState.body.contains("\"palette\":[\"#DB2A52\""), true, "web console /state reflects the Default palette's first color")
            check(consoleState.body.contains("\"paletteTextColors\":[\"#ffffff\""), true, "web console /state reflects the Default palette's first text color")
        } else {
            failures += 1
            print("FAIL [palette in web console state]: no response")
        }
        if let vkState = syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test") {
            check(vkState.body.contains("\"palette\":[\"#DB2A52\""), true, "virtual keyboard /state reflects the Default palette's first color")
            check(vkState.body.contains("\"paletteTextColors\":[\"#ffffff\""), true, "virtual keyboard /state reflects the Default palette's first text color")
        } else {
            failures += 1
            print("FAIL [palette in virtual keyboard state]: no response")
        }

        try session.selectColorPalette(named: "Pastel")
        Thread.sleep(forTimeInterval: 0.3)

        if let consoleState = syncGET("http://127.0.0.1:18400/state") {
            check(consoleState.body.contains("\"palette\":[\"#FFADAD\""), true, "web console /state reflects the switch to Pastel on the next poll")
            check(consoleState.body.contains("\"paletteTextColors\":[\"#111111\""), true, "web console /state reflects Pastel's all-black text colors on the next poll")
        } else {
            failures += 1
            print("FAIL [palette switch in web console state]: no response")
        }
        if let vkState = syncGET("http://127.0.0.1:18401/state?client=palette-test&name=Test") {
            check(vkState.body.contains("\"palette\":[\"#FFADAD\""), true, "virtual keyboard /state reflects the switch to Pastel on the next poll")
            check(vkState.body.contains("\"paletteTextColors\":[\"#111111\""), true, "virtual keyboard /state reflects Pastel's all-black text colors on the next poll")
        } else {
            failures += 1
            print("FAIL [palette switch in virtual keyboard state]: no response")
        }

        session.stopWebConsole()
        session.stopVirtualKeyboard()
    } catch {
        failures += 1
        print("FAIL [palette in HTTP state]: threw \(error)")
    }
}
testActiveColorPaletteIsReflectedInWebConsoleAndVirtualKeyboardState()

func testGuideSequenceSaveAndLoadRoundTrips() {
    do {
        let session = ImprovSession()
        session.newGuideSequence(title: "Round Trip")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        check(reloaded.currentGuide, session.currentGuide, "guide sequence round-trips through JSON")
        checkNil(reloaded.currentGuideStepIndex, "loading a guide sequence resets the current step index")
    } catch {
        failures += 1
        print("FAIL [guide sequence save/load round trip]: threw \(error)")
    }
}

func testGuideStepWithChordProgressionRoundTripsThroughJSON() {
    do {
        let session = ImprovSession()
        session.newGuideSequence(title: "With Progression")
        let blues = ChordProgressionTemplate.builtInDefaults[0] // "Blues 12 mesures"
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"), chordProgression: blues)

        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.saveGuideSequence(toJSONFile: tempFile.path)

        let reloaded = ImprovSession()
        try reloaded.loadGuideSequence(fromJSONFile: tempFile.path)
        check(reloaded.currentGuide?.steps.first?.chordProgressionName, "Blues 12 mesures", "chord progression name round-trips")
        check(reloaded.currentGuide?.steps.first?.chordProgression?.count, 12, "chord progression round-trips with all 12 chords")
    } catch {
        failures += 1
        print("FAIL [guide step chord progression round trip]: threw \(error)")
    }
}

/// Every guide file saved before chord progressions existed stores each step as a bare
/// `ModeReference` (no "mode" key) — `GuideStep.init(from:)` must still load these.
func testGuideStepDecodesOldBareModeReferenceFormat() {
    let json = #"{"title":"Old Format","steps":[{"scaleID":"dorian","tonic":2}]}"#.data(using: .utf8)!
    do {
        let decoded = try JSONDecoder().decode(GuideSequence.self, from: json)
        check(decoded.steps.count, 1, "old-format guide file decodes its one step")
        check(decoded.steps.first?.mode, ModeReference(tonic: 2, scaleID: "dorian"), "old-format step's bare ModeReference becomes GuideStep.mode")
        checkNil(decoded.steps.first?.chordProgressionName, "old-format step has no chord progression name")
        checkNil(decoded.steps.first?.chordProgression, "old-format step has no chord progression")
    } catch {
        failures += 1
        print("FAIL [old-format guide step decode]: threw \(error)")
    }
}

func testRomanNumeralChordParseHandlesUpperLowerAndDiminished() {
    check(RomanNumeralChord.parse("I")?.quality, .major, "I is major")
    check(RomanNumeralChord.parse("I")?.degree, 1, "I is degree 1")
    check(RomanNumeralChord.parse("vi")?.quality, .minor, "vi is minor")
    check(RomanNumeralChord.parse("vi")?.degree, 6, "vi is degree 6")
    check(RomanNumeralChord.parse("vii°")?.quality, .diminished, "vii° is diminished")
    check(RomanNumeralChord.parse("vii°")?.degree, 7, "vii° is degree 7")
    checkNil(RomanNumeralChord.parse("VIII"), "VIII is not a valid roman numeral (out of range)")
    checkNil(RomanNumeralChord.parse("xyz"), "garbage text does not parse")
}

func testResolveChordProgressionAppliesLiteralCaseAsQualityInCIonian() {
    let session = ImprovSession()
    let mode = Mode(tonic: PitchClass(0), scale: ScaleLibrary.byID("ionian")!)
    let blues = ChordProgressionTemplate.builtInDefaults[0] // I I I I IV IV I I V IV I I
    let resolved = session.resolveChordProgression(blues, in: mode)
    check(resolved.count, 12, "blues progression resolves to 12 chords")
    check(resolved.first?.root, 0, "first chord (I) is rooted on C")
    check(resolved.first?.chordTemplateID, "Ma", "I is taken literally as major")
    check(resolved[4].root, 5, "5th chord (IV) is rooted on F")
    check(resolved[8].root, 7, "9th chord (V) is rooted on G")
}

// MARK: - Run





testLoadDemoPieceSetsPieceAndLogsIt()
testPlayWithoutAPieceLoadedThrows()
testPlayTracksPlaybackStateSynchronouslyThenClearsItWhenFinished()
testSetPieceTrackInstrumentUpdatesTrackAndLogs()
testSetPieceTrackInstrumentNilRevertsToEmptyString()
testSetPieceTrackInstrumentWithInvalidSectionIndexThrows()
testSetPieceTrackInstrumentWithInvalidTrackIndexThrows()
testSetPieceChordInstrumentUpdatesSectionAndLogs()
testSetPieceChordInstrumentWithInvalidSectionIndexThrows()
testPlayWarnsWhenATracksInstrumentFileIsNotFound()
testPlayWithoutAnyTrackInstrumentLogsNoInstrumentWarning()
testStartTrackOnAnUnlistedMIDIPortThrows()
testDefaultMIDIFusionModeIsIndividual()
testSetMIDIFusionModeSwitchesTrackList()
testMicrophoneTrackCannotHaveSound()
testSetMicrophoneRecognitionModeRejectsNonMicrophoneTrack()
testSetMicrophoneRecognitionModeRejectsInvalidWindowCount()
testSetMicrophoneRecognitionModeSurvivesTrackRestart()
testMicrophonePolyLatchedDoesNotConfirmAFlickeringNote()
testMicrophonePolySlidingConfirmsUnderMajorityDespiteOneDropout()
testMicrophoneMonophonicModeConfirmsImmediately()
testSaveThenLoadRoundTripsThePieceThroughJSON()
testLoadingAMissingFileThrows()
testListPieceFilesFindsJSONFilesAndIgnoresOthers()
testUsePieceByIndexAndNameLoadFromTheListedFolder()
testSaveWithoutEverLoadingOrSavingThrows()
testSaveAsThenBareSaveRoundTripToTheSameFile()
testSaveAsWithoutAPieceFolderListedThrowsForABareName()

testNewGuideSequenceThenAddStepsThenStartAndAdvance()
testAddGuideStepWithoutASequenceThrows()
testAddGuideStepWithUnknownScaleIDThrowsAndDoesNotAppendAStep()
testGuideSequenceSaveAndLoadRoundTrips()
testGuideStepWithChordProgressionRoundTripsThroughJSON()
testGuideStepDecodesOldBareModeReferenceFormat()
testRomanNumeralChordParseHandlesUpperLowerAndDiminished()
testResolveChordProgressionAppliesLiteralCaseAsQualityInCIonian()
testTrackIDWireIDTextRoundTrips()
testSceneSaveAndLoadRoundTripsTrackListeningAndSound()
testLoadSceneLeavesTracksNotMentionedUntouched()


func testHandlingIncomingMIDIEventsDetectsChordPerTrack() {
    checks += 1
    do {
        let session = ImprovSession()
        // Default fusion mode is now `.individual` (no `.midiMerged` track exists until
        // switched) — this test exercises `.midiMerged` specifically, not the default.
        session.setMIDIFusionMode(.merged)
        // Sound stays off on this track, so this never touches the (unstarted) audio engine.
        try session.startTrack(.midiMerged)
        for pitch in [60, 64, 67, 71] {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
        }
        let recognizedChord = session.tracks.first { $0.id == .midiMerged }?.recognizedChord
        if recognizedChord?.root != PitchClass(0) || recognizedChord?.chordTemplateID != "Ma7" {
            failures += 1
            print("FAIL [session handles MIDI events, detects chord]: \(String(describing: recognizedChord))")
        }
        session.stopTrack(.midiMerged)
        let chordAfterStop = session.tracks.first { $0.id == .midiMerged }?.recognizedChord
        if chordAfterStop != nil {
            failures += 1
            print("FAIL [session clears chord on stopTrack]: \(String(describing: chordAfterStop))")
        }
    } catch {
        failures += 1
        print("FAIL [session handles MIDI events, detects chord]: threw \(error)")
    }
}
testHandlingIncomingMIDIEventsDetectsChordPerTrack()

func testTrackRecordsMostRecentMIDIChannel() {
    let session = ImprovSession()
    session.setMIDIFusionMode(.merged)
    do {
        try session.startTrack(.midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, nil, "lastChannel is nil before any note event")
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 3), track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 3, "lastChannel reflects the most recent note event's channel")
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 7), track: .midiMerged)
        check(session.tracks.first { $0.id == .midiMerged }?.lastChannel, 7, "lastChannel updates on a later event with a different channel")
    } catch {
        failures += 1
        print("FAIL [track records most recent MIDI channel]: threw \(error)")
    }
}
testTrackRecordsMostRecentMIDIChannel()

// Deliberately single notes throughout (not a 3-note chord built one pitch at a time) to keep
// the expected event count unambiguous — playing a chord note by note legitimately produces
// one event per intermediate held-pitches snapshot (1 note, then 2, then 3), the whole point of
// this feature (nothing in between gets skipped), not something to work around here.
func testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease() {
    checks += 1
    do {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }

        if events().count != 0 {
            failures += 1
            print("FAIL [recentChordEvents starts empty]: \(events().count)")
        }

        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 60, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 1 || events().last?.pitches != [60] {
            failures += 1
            print("FAIL [recentChordEvents records first note]: \(events())")
        }

        // A full release must NOT append a blank "rest" entry — the pitch-60 event stays last.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: 60, velocity: 0, channel: 0), track: .midiMerged)
        if events().count != 1 {
            failures += 1
            print("FAIL [recentChordEvents skips a blank rest entry on full release]: \(events())")
        }

        // A different note is a genuinely new, distinct event.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 2 || events().last?.pitches != [62] {
            failures += 1
            print("FAIL [recentChordEvents records a second distinct note]: \(events())")
        }

        // Repeated note-on for an already-held pitch (e.g. a hardware retrigger) is the exact
        // same snapshot again — must not append a duplicate.
        session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: 62, velocity: 100, channel: 0), track: .midiMerged)
        if events().count != 2 {
            failures += 1
            print("FAIL [recentChordEvents skips a duplicate of the unchanged snapshot]: \(events())")
        }

        session.stopTrack(.midiMerged)
        if events().count != 0 {
            failures += 1
            print("FAIL [recentChordEvents clears on stopTrack]: \(events())")
        }
    } catch {
        failures += 1
        print("FAIL [recentChordEvents]: threw \(error)")
    }
}
testRecentChordEventsLogsChangesAndSkipsRestsOnFullRelease()

func testRecentChordEventsCapsAtTwentyEntries() {
    checks += 1
    do {
        let session = ImprovSession()
        session.setMIDIFusionMode(.merged) // default is now .individual; this test needs .midiMerged specifically
        try session.startTrack(.midiMerged)
        func events() -> [WebConsoleChordEvent] {
            session.buildWebConsoleState().tracks.first { $0.id == "midi" }?.recentChordEvents ?? []
        }
        for pitch in 60..<85 {
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOn, pitch: pitch, velocity: 100, channel: 0), track: .midiMerged)
            session.handleIncomingMIDIEvent(MIDINoteEvent(kind: .noteOff, pitch: pitch, velocity: 0, channel: 0), track: .midiMerged)
        }
        if events().count != 20 || events().last?.pitches != [84] || events().first?.pitches != [65] {
            failures += 1
            print("FAIL [recentChordEvents caps at 20 entries]: count=\(events().count) first=\(String(describing: events().first?.pitches)) last=\(String(describing: events().last?.pitches))")
        }
    } catch {
        failures += 1
        print("FAIL [recentChordEvents caps at 20 entries]: threw \(error)")
    }
}
testRecentChordEventsCapsAtTwentyEntries()

// MARK: - Read-only structure detail (piece/composition/guide/soundtrack) — mirrors
// Tests/AppCoreTests/ImprovSessionTests.swift's tests of the same name.

func testBuildPieceDetailReflectsWholeStructureIncludingEmptyTracks() {
    do {
        let session = ImprovSession()
        check(session.buildPieceDetail().loaded, false, "buildPieceDetail reports not loaded with no piece")

        let trackWithNotes = Track(name: "lead", instrument: "mcb.sf2", melodyEvents: [
            MelodyEvent(measure: 1, beat: 1, durationBeats: 1, pitch: 60),
        ])
        // The real regression this route fixes: `pieceDetailLines()` (the terminal's own
        // piece display) silently skips any track with zero `melodyEvents` — a fragment-only
        // track just vanishes. `buildPieceDetail()` must not repeat that mistake.
        let emptyTrack = Track(name: "fragment-only", instrument: "")
        let chord = ChordEvent(measure: 1, beat: 1, durationBeats: 4, chord: ChordReference(root: 0, chordTemplateID: "Ma7"))
        let section = Section(
            name: "A", lengthInMeasures: 1, mode: ModeReference(tonic: 0, scaleID: "ionian"),
            chordProgression: [chord], tracks: [trackWithNotes, emptyTrack]
        )
        let piece = Piece(title: "Detail Test", tempoBPM: 120, key: ModeReference(tonic: 0, scaleID: "ionian"), sections: [section])
        let tempFile = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".json")
        try JSONEncoder().encode(piece).write(to: tempFile)
        defer { try? FileManager.default.removeItem(at: tempFile) }
        try session.loadPiece(fromJSONFile: tempFile.path)

        let detail = session.buildPieceDetail()
        check(detail.loaded, true, "buildPieceDetail reports loaded once a piece is loaded")
        check(detail.sections?.count, 1, "buildPieceDetail section count")
        check(detail.sections?[0].chordProgression.first?.chord.label, "CMa7", "buildPieceDetail resolves a chord label")
        check(detail.sections?[0].tracks.count, 2, "buildPieceDetail keeps every track, including empty ones")
        let hasEmptyTrack = detail.sections?[0].tracks.contains { $0.name == "fragment-only" && $0.melodyEvents.isEmpty } ?? false
        check(hasEmptyTrack, true, "buildPieceDetail includes a track with zero melody events")
    } catch {
        failures += 1
        print("FAIL [buildPieceDetail]: threw \(error)")
    }
}
testBuildPieceDetailReflectsWholeStructureIncludingEmptyTracks()

func testBuildCompositionDetailReflectsStagedTextAndResolvedPrompt() {
    let session = ImprovSession()
    let empty = session.buildCompositionDetail()
    checkNil(empty.sourceText, "buildCompositionDetail has no source text before anything is staged")
    checkNil(empty.resolvedPrompt, "buildCompositionDetail has no resolved prompt before anything is staged")

    session.setSourceText("a quiet lake at dusk")
    session.setCompositionTitle("Lake Piece")
    session.setAdditionalCompositionInstructions("impressionist, slow tempo")

    let detail = session.buildCompositionDetail()
    check(detail.title, "Lake Piece", "buildCompositionDetail title")
    check(detail.sourceText, "a quiet lake at dusk", "buildCompositionDetail source text")
    check(detail.additionalInstructions, "impressionist, slow tempo", "buildCompositionDetail instructions")
    check(detail.resolvedPrompt?.contains("a quiet lake at dusk") ?? false, true, "buildCompositionDetail resolved prompt contains the source text")
}
testBuildCompositionDetailReflectsStagedTextAndResolvedPrompt()

func testBuildGuideDetailReflectsAllStepsNotJustCurrent() {
    do {
        let session = ImprovSession()
        check(session.buildGuideDetail().loaded, false, "buildGuideDetail reports not loaded with no guide")

        session.newGuideSequence(title: "Explore")
        try session.addGuideStep(ModeReference(tonic: 0, scaleID: "ionian"))
        try session.addGuideStep(ModeReference(tonic: 7, scaleID: "mixolydian"))
        try session.startGuide()

        let detail = session.buildGuideDetail()
        check(detail.loaded, true, "buildGuideDetail reports loaded once a guide is loaded")
        check(detail.title, "Explore", "buildGuideDetail title")
        check(detail.steps?.count, 2, "buildGuideDetail step count")
        check(detail.currentStepIndex, 0, "buildGuideDetail current step index")
        check(detail.steps?[0].isCurrent, true, "buildGuideDetail flags the current step")
        // The real regression this route fixes: `GET /state`'s own `guide` field only ever
        // exposes the CURRENT step's mode/chords — a non-current step's own detail must
        // still be reported here.
        check(detail.steps?[1].isCurrent, false, "buildGuideDetail correctly flags a non-current step")
        check(detail.steps?[1].mode.scaleID, "mixolydian", "buildGuideDetail reports a non-current step's own scale")
        check(detail.steps?[1].mode.tonicName, "G", "buildGuideDetail reports a non-current step's own tonic name")
    } catch {
        failures += 1
        print("FAIL [buildGuideDetail]: threw \(error)")
    }
}
testBuildGuideDetailReflectsAllStepsNotJustCurrent()

func testBuildSoundTrackDetailReflectsEventsAndTrackIDs() {
    do {
        let session = ImprovSession()
        check(session.buildSoundTrackDetail().loaded, false, "buildSoundTrackDetail reports not loaded with no soundtrack")

        try session.startRecording(title: "Detail Test")
        session.pressKey(pitch: 60)
        session.releaseKey(pitch: 60)
        _ = try session.stopRecording()

        let detail = session.buildSoundTrackDetail()
        check(detail.loaded, true, "buildSoundTrackDetail reports loaded once a soundtrack is recorded")
        check(detail.title, "Detail Test", "buildSoundTrackDetail title")
        check(detail.events?.count, 2, "buildSoundTrackDetail event count")
        check(detail.trackIDs, ["clavier"], "buildSoundTrackDetail track ids")
    } catch {
        failures += 1
        print("FAIL [buildSoundTrackDetail]: threw \(error)")
    }
}
testBuildSoundTrackDetailReflectsEventsAndTrackIDs()

func testNewPieceStartsBlank() {
    let session = ImprovSession()
    session.newPiece(title: "My Poem Piece")
    check(session.piece?.title, "My Poem Piece", "new piece title")
    check(session.piece?.sections, [], "new piece starts with no sections")
    checkNil(session.currentPieceFilePath, "new piece has no current file")
}

func testSetSourceTextStoresItAndLogs() {
    let session = ImprovSession()
    session.setSourceText("Roses are red")
    check(session.sourceText, "Roses are red", "source text stored")
    checks += 1
    if !session.log.contains(where: { $0.contains("Source text set") }) {
        failures += 1
        print("FAIL [source text logs it]: \(session.log)")
    }
}

func testListLLMConnectionsFindsJSONFiles() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))
        try Data().write(to: folder.appendingPathComponent("notes.txt"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        if session.llmConnections != ["ollama.json"] {
            failures += 1
            print("FAIL [list llm connections finds json]: \(session.llmConnections)")
        }
    } catch {
        failures += 1
        print("FAIL [list llm connections finds json]: threw \(error)")
    }
}

func testUseLLMConnectionByIndexAndNameLoadFromTheListedFolder() {
    checks += 2
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let connection = LLMConnection(name: "Local Ollama", provider: "ollama", baseURL: "http://localhost:11434", model: "llama3")
        try JSONEncoder().encode(connection).write(to: folder.appendingPathComponent("ollama.json"))

        let session = ImprovSession()
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)
        if session.currentLLMConnection != connection {
            failures += 1
            print("FAIL [use-llm by index]: \(String(describing: session.currentLLMConnection))")
        }

        let byName = ImprovSession()
        try byName.listLLMConnections(in: folder.path)
        try byName.useLLMConnection(named: "ollama.json")
        if byName.currentLLMConnection != connection {
            failures += 1
            print("FAIL [use-llm by name]: \(String(describing: byName.currentLLMConnection))")
        }
    } catch {
        failures += 2
        print("FAIL [use-llm by index/name]: threw \(error)")
    }
}

func testComposeFromTextWithoutSourceTextThrows() {
    checks += 1
    do {
        let session = ImprovSession()
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "x", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("x.json"))
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        try session.composeFromText()
        failures += 1
        print("FAIL [compose without source text throws]: did not throw")
    } catch let error as ImprovSession.SessionError where error == .noSourceText {
        // expected
    } catch {
        failures += 1
        print("FAIL [compose without source text throws]: wrong error \(error)")
    }
}

func testComposeFromTextWithoutAConnectionThrows() {
    let session = ImprovSession()
    session.setSourceText("a poem")
    checks += 1
    do {
        try session.composeFromText()
        failures += 1
        print("FAIL [compose without connection throws]: did not throw")
    } catch let error as ImprovSession.SessionError where error == .noLLMConnectionSelected {
        // expected
    } catch {
        failures += 1
        print("FAIL [compose without connection throws]: wrong error \(error)")
    }
}

func testComposeFromTextWithAFakeGeneratorProducesAValidatedPiece() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { _, _ in fakeResponse }

        if session.piece?.title != "The Sea" {
            failures += 1
            print("FAIL [compose with fake generator]: \(String(describing: session.piece?.title))")
        }
    } catch {
        failures += 1
        print("FAIL [compose with fake generator]: threw \(error)")
    }
}

func testComposeFromTextWithInvalidResponseThrowsWithWarnings() {
    checks += 1
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        try session.composeFromText { _, _ in "not json at all" }
        failures += 1
        print("FAIL [compose with invalid response throws]: did not throw")
    } catch let error as ImprovSession.SessionError {
        if case .llmComposeFailed = error {
            // expected
        } else {
            failures += 1
            print("FAIL [compose with invalid response throws llmComposeFailed]: got \(error)")
        }
    } catch {
        failures += 1
        print("FAIL [compose with invalid response throws]: threw \(error)")
    }
}

func testComposeFromTextWithATitleOverridesTheLLMsOwnTitle() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "LLM Chosen Title", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText(title: "My Own Title") { _, _ in fakeResponse }
        check(session.piece?.title, "My Own Title", "composeFromText title override wins over the LLM's own title")
    } catch {
        failures += 1
        print("FAIL [compose from text with title override]: threw \(error)")
    }
}
testComposeFromTextWithATitleOverridesTheLLMsOwnTitle()

func testSetAdditionalCompositionInstructionsAreIncludedInThePrompt() {
    do {
        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        let prompt = try session.currentTextCompositionPrompt()
        checks += 1
        if !prompt.contains("romantique, mode mineur") || !prompt.contains("a poem about the sea") {
            failures += 1
            print("FAIL [additional composition instructions included in prompt]: \(prompt)")
        }
    } catch {
        failures += 1
        print("FAIL [additional composition instructions included in prompt]: threw \(error)")
    }
}
testSetAdditionalCompositionInstructionsAreIncludedInThePrompt()

func testSetAdditionalCompositionInstructionsEmptyStringClearsThem() {
    let session = ImprovSession()
    session.setAdditionalCompositionInstructions("romantique")
    check(session.additionalCompositionInstructions, "romantique", "setAdditionalCompositionInstructions stores the text")
    session.setAdditionalCompositionInstructions("")
    checkNil(session.additionalCompositionInstructions, "setAdditionalCompositionInstructions('') clears them")
}
testSetAdditionalCompositionInstructionsEmptyStringClearsThem()

func testSetCompositionTitleEmptyStringClearsIt() {
    let session = ImprovSession()
    session.setCompositionTitle("Ma Ballade")
    check(session.compositionTitle, "Ma Ballade", "setCompositionTitle stores the title")
    session.setCompositionTitle("")
    checkNil(session.compositionTitle, "setCompositionTitle('') clears it")
    session.setCompositionTitle(nil)
    checkNil(session.compositionTitle, "setCompositionTitle(nil) clears it")
}
testSetCompositionTitleEmptyStringClearsIt()

func testComposeFromTextSendsAdditionalInstructionsInThePrompt() {
    do {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        try JSONEncoder().encode(LLMConnection(name: "Fake", provider: "ollama", baseURL: "http://x", model: "x"))
            .write(to: folder.appendingPathComponent("fake.json"))

        let session = ImprovSession()
        session.setSourceText("a poem about the sea")
        session.setAdditionalCompositionInstructions("romantique, mode mineur")
        try session.listLLMConnections(in: folder.path)
        try session.useLLMConnection(atIndex: 0)

        let fakeResponse = """
        { "title": "The Sea", "tempoBPM": 80, "tonic": "D", "scaleID": "dorian",
          "sections": [ { "name": "A", "lengthInMeasures": 1, "tonic": "D", "scaleID": "dorian",
            "chords": [ { "measure": 1, "root": "D", "templateID": "mi7" } ] } ] }
        """
        try session.composeFromText { prompt, _ in
            checks += 1
            if !prompt.contains("romantique, mode mineur") {
                failures += 1
                print("FAIL [compose from text sends additional instructions]: \(prompt)")
            }
            return fakeResponse
        }
    } catch {
        failures += 1
        print("FAIL [compose from text sends additional instructions]: threw \(error)")
    }
}
testComposeFromTextSendsAdditionalInstructionsInThePrompt()

testNewPieceStartsBlank()
testSetSourceTextStoresItAndLogs()
testListLLMConnectionsFindsJSONFiles()
testUseLLMConnectionByIndexAndNameLoadFromTheListedFolder()
testComposeFromTextWithoutSourceTextThrows()
testComposeFromTextWithoutAConnectionThrows()
testComposeFromTextWithAFakeGeneratorProducesAValidatedPiece()
testComposeFromTextWithInvalidResponseThrowsWithWarnings()


print("\(checks) checks, \(failures) failures")
if failures > 0 {
    exit(1)
}
