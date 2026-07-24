import SwiftUI

/// Maps a typed character to a MIDI pitch, mirroring GarageBand's "Musical Typing" layout —
/// same mapping `Sources/JamShack/main.swift`'s own `computerKeyboardNoteMap` uses (kept as a
/// separate copy here rather than a shared module: the CLI's copy lives in an executable
/// target, not a library, so sharing it would mean restructuring a working terminal app for
/// no functional gain — same "can't share code across these presentation layers" situation as
/// WebConsole's JS). "ASDFGHJKL;" plays the white keys of one octave starting at C4,
/// "WE_TYU_OP" fills in the black keys above the gaps.
public let computerKeyboardNoteMap: [Character: Int] = [
    "a": 60, "w": 61, "s": 62, "e": 63, "d": 64, "f": 65, "t": 66, "g": 67,
    "y": 68, "h": 69, "u": 70, "j": 71, "k": 72, "o": 73, "l": 74, "p": 75, ";": 76,
]

public extension View {
    /// Plays notes from the physical/hardware keyboard while this view (or one of its
    /// descendants) is focused, via `computerKeyboardNoteMap`. Unlike the terminal CLI (which
    /// only ever gets "this character was typed," no key-up, and so has to fake a fixed-length
    /// "tap" — see `triggerComputerKeyboardNote`'s doc comment in `JamShack/main.swift`), a
    /// real GUI gets true key-down/key-up events, so this drives a genuine sustain-while-held
    /// instead of a timed pluck — a real improvement the CLI's environment can't offer.
    func computerKeyboardInput(isActive: Bool = true, onNoteOn: @escaping (Int) -> Void, onNoteOff: @escaping (Int) -> Void) -> some View {
        background(ComputerKeyboardCaptureRepresentable(isActive: isActive, onNoteOn: onNoteOn, onNoteOff: onNoteOff))
    }
}

#if os(macOS)
import AppKit

final class KeyCaptureNSView: NSView {
    var onNoteOn: ((Int) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(self)
    }

    override func keyDown(with event: NSEvent) {
        // Ignore key-repeat: holding a key down must sustain the note (already true — it's
        // simply never released), not re-trigger pressKey on every OS auto-repeat tick.
        guard !event.isARepeat,
              let character = event.charactersIgnoringModifiers?.lowercased().first,
              let pitch = computerKeyboardNoteMap[character]
        else {
            super.keyDown(with: event)
            return
        }
        onNoteOn?(pitch)
    }

    override func keyUp(with event: NSEvent) {
        guard let character = event.charactersIgnoringModifiers?.lowercased().first,
              let pitch = computerKeyboardNoteMap[character]
        else {
            super.keyUp(with: event)
            return
        }
        onNoteOff?(pitch)
    }
}

struct ComputerKeyboardCaptureRepresentable: NSViewRepresentable {
    let isActive: Bool
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    func makeNSView(context: Context) -> KeyCaptureNSView {
        let view = KeyCaptureNSView()
        view.onNoteOn = onNoteOn
        view.onNoteOff = onNoteOff
        return view
    }

    func updateNSView(_ nsView: KeyCaptureNSView, context: Context) {
        nsView.onNoteOn = onNoteOn
        nsView.onNoteOff = onNoteOff
        if isActive {
            DispatchQueue.main.async { nsView.window?.makeFirstResponder(nsView) }
        }
    }
}
#endif

#if os(iOS)
import UIKit

final class KeyCaptureUIView: UIView {
    var onNoteOn: ((Int) -> Void)?
    var onNoteOff: ((Int) -> Void)?

    override var canBecomeFirstResponder: Bool { true }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        becomeFirstResponder()
    }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key,
                  let character = key.charactersIgnoringModifiers.lowercased().first,
                  let pitch = computerKeyboardNoteMap[character]
            else {
                unhandled.insert(press)
                continue
            }
            onNoteOn?(pitch)
        }
        if !unhandled.isEmpty { super.pressesBegan(unhandled, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled: Set<UIPress> = []
        for press in presses {
            guard let key = press.key,
                  let character = key.charactersIgnoringModifiers.lowercased().first,
                  let pitch = computerKeyboardNoteMap[character]
            else {
                unhandled.insert(press)
                continue
            }
            onNoteOff?(pitch)
        }
        if !unhandled.isEmpty { super.pressesEnded(unhandled, with: event) }
    }
}

struct ComputerKeyboardCaptureRepresentable: UIViewRepresentable {
    let isActive: Bool
    let onNoteOn: (Int) -> Void
    let onNoteOff: (Int) -> Void

    func makeUIView(context: Context) -> KeyCaptureUIView {
        let view = KeyCaptureUIView()
        view.onNoteOn = onNoteOn
        view.onNoteOff = onNoteOff
        return view
    }

    func updateUIView(_ uiView: KeyCaptureUIView, context: Context) {
        uiView.onNoteOn = onNoteOn
        uiView.onNoteOff = onNoteOff
        if isActive, !uiView.isFirstResponder {
            uiView.becomeFirstResponder()
        }
    }
}
#endif
