import Foundation
#if canImport(Darwin)
import Darwin
#endif

// MARK: - Raw terminal input

/// Toggles canonical-mode + echo on the controlling terminal. Off (raw) lets us read
/// single keystrokes (arrow keys, Enter, Escape) immediately instead of waiting for a
/// line + Enter; on (canonical) is normal shell-like line editing, used while a menu
/// action is prompting for text. Idempotent either way — safe to call redundantly.
func setRawMode(_ raw: Bool) {
    var settings = termios()
    tcgetattr(STDIN_FILENO, &settings)
    if raw {
        settings.c_lflag &= ~UInt(ECHO | ICANON)
    } else {
        settings.c_lflag |= UInt(ECHO | ICANON)
    }
    tcsetattr(STDIN_FILENO, TCSANOW, &settings)
}

enum Key: Equatable {
    case char(Character)
    case up, down, left, right
    case enter, escape, tab
}

/// Checks whether `STDIN_FILENO` has a byte ready, without blocking — via `poll(2)`, not
/// `O_NONBLOCK` on the fd. Setting `O_NONBLOCK` on stdin used to be how `readKey()` avoided
/// blocking, but under the standard way an interactive shell attaches to a terminal
/// (`login_tty(3)`-style: the pty slave is opened once and `dup2`'d onto fd 0/1/2), stdin,
/// stdout and stderr all share the *same* underlying open file description — so making
/// stdin non-blocking made stdout non-blocking too. A write that then hit a momentarily-full
/// pty buffer either silently dropped data (plain `print`, the likely cause of "the keyboard
/// sometimes draws incompletely") or threw an uncaught exception and crashed the process
/// (`FileHandle.write`, confirmed by reproducing it directly — `NSFileHandleOperationException
/// ... Resource temporarily unavailable`, i.e. EAGAIN on the write). `poll` lets stdin be
/// checked without touching the fd's blocking mode at all, so stdout is never affected.
private func stdinHasByteAvailable() -> Bool {
    var pfd = pollfd(fd: STDIN_FILENO, events: Int16(POLLIN), revents: 0)
    guard poll(&pfd, 1, 0) > 0 else { return false }
    return Int32(pfd.revents) & POLLIN != 0
}

/// Single-key read, without blocking if nothing is waiting: arrow keys arrive as a 3-byte
/// escape sequence (`ESC [ A/B/C/D`), so seeing a bare ESC byte peeks ahead briefly for the
/// rest of the sequence before deciding it's a standalone Escape press.
func readKey() -> Key? {
    guard stdinHasByteAvailable() else { return nil }
    var first: UInt8 = 0
    guard read(STDIN_FILENO, &first, 1) == 1 else { return nil }

    if first == 27 { // ESC
        usleep(2000) // give a follow-up escape sequence a moment to arrive
        guard stdinHasByteAvailable() else { return .escape }
        var second: UInt8 = 0
        guard read(STDIN_FILENO, &second, 1) == 1, second == UInt8(ascii: "[") else { return .escape }
        guard stdinHasByteAvailable() else { return .escape }
        var third: UInt8 = 0
        guard read(STDIN_FILENO, &third, 1) == 1 else { return .escape }
        switch third {
        case UInt8(ascii: "A"): return .up
        case UInt8(ascii: "B"): return .down
        case UInt8(ascii: "C"): return .right
        case UInt8(ascii: "D"): return .left
        default: return .escape
        }
    }
    if first == 13 || first == 10 { return .enter }
    if first == 9 { return .tab }
    return Unicode.Scalar(UInt32(first)).map { .char(Character($0)) }
}

// MARK: - Menu model

struct MenuItem {
    let label: String
    let action: () throws -> Void
    let isSeparator: Bool

    init(label: String, action: @escaping () throws -> Void) {
        self.label = label
        self.action = action
        self.isSeparator = false
    }

    /// A non-selectable divider line inside a dropdown, for grouping related items — never
    /// landed on by up/down navigation (see `handleMenuKey`), so its `action` is never run.
    nonisolated(unsafe) static let separator = MenuItem(label: "", isSeparator: true)

    /// Same non-selectable behavior as `separator`, but with a title rendered dimmed inside
    /// the box — a named sub-section within one dropdown (e.g. "Assistant IA" inside
    /// `Morceaux`), since this app's menus are a flat list per category with no real nested
    /// submenus.
    static func header(_ title: String) -> MenuItem {
        MenuItem(label: title, isSeparator: true)
    }

    private init(label: String, isSeparator: Bool) {
        self.label = label
        self.action = {}
        self.isSeparator = isSeparator
    }
}

struct MenuCategory {
    let mnemonic: Character
    let title: String
    let items: [MenuItem]
}

nonisolated(unsafe) var openMenuIndex: Int?
nonisolated(unsafe) var selectedItemIndex = 0

/// A menu action always runs with the terminal back in normal line-editing mode and a
/// freshly cleared screen — actions are free to `print`/`promptLine` as much as they like
/// (folder → numbered list → choice, confirmations, errors...) without worrying about the
/// live dashboard's redraw-in-place conventions. A "press Enter" pause at the end means
/// whatever it printed stays readable before the dashboard takes back over.
func runMenuAction(_ action: () throws -> Void) {
    // `readLine()` (used by the action itself, and below for the "press Enter" pause) needs
    // normal canonical-mode input — raw mode has to come off for the duration.
    setRawMode(false)
    print("\u{1B}[2J\u{1B}[H", terminator: "")
    do {
        try action()
        drainLog()
    } catch {
        print("Erreur: \(error)")
    }
    print("\n(Entree pour revenir a l'ecran)", terminator: "")
    _ = readLine()
    setRawMode(true)
    print("\u{1B}[2J", terminator: "")
}

/// Text input for a menu action, while it's running in the paused/canonical context
/// `runMenuAction` already set up — a thin wrapper over `readLine()` so actions read
/// naturally top to bottom (prompt, then answer) like a plain script.
func promptLine(_ prompt: String) -> String? {
    print(prompt, terminator: "")
    return readLine()
}

func handleMenuKey(_ key: Key, categories: [MenuCategory]) {
    if let openIndex = openMenuIndex {
        let items = categories[openIndex].items
        switch key {
        case .up:
            var next = (selectedItemIndex - 1 + items.count) % items.count
            while items[next].isSeparator { next = (next - 1 + items.count) % items.count }
            selectedItemIndex = next
        case .down:
            var next = (selectedItemIndex + 1) % items.count
            while items[next].isSeparator { next = (next + 1) % items.count }
            selectedItemIndex = next
        case .left:
            openMenuIndex = (openIndex - 1 + categories.count) % categories.count
            selectedItemIndex = 0
        case .right:
            openMenuIndex = (openIndex + 1) % categories.count
            selectedItemIndex = 0
        case .escape:
            openMenuIndex = nil
        case .enter:
            let action = items[selectedItemIndex].action
            openMenuIndex = nil
            runMenuAction(action)
        case .char(let c):
            if let match = categories.firstIndex(where: { $0.mnemonic.lowercased() == String(c).lowercased() }) {
                openMenuIndex = match
                selectedItemIndex = 0
            }
        case .tab:
            break // handled one level up, in `runConsoleScreen` — screen switching isn't a menu concern
        }
    } else {
        switch key {
        case .char(let c):
            if let match = categories.firstIndex(where: { $0.mnemonic.lowercased() == String(c).lowercased() }) {
                openMenuIndex = match
                selectedItemIndex = 0
            }
        case .left, .right, .escape:
            // Escape alongside the arrows: a way into the menu that isn't a letter, so it
            // stays available even when letter mnemonics are disabled (see "Source clavier"
            // in ImprovCLI/main.swift, which relies on this to get back to the menu).
            openMenuIndex = 0
            selectedItemIndex = 0
        default:
            break
        }
    }
}

/// The menu bar line: each category's mnemonic letter underlined, the whole label in
/// reverse video while its dropdown is open. Underlines wherever the mnemonic actually
/// occurs in the title rather than assuming it's always the first letter — "IA" uses
/// mnemonic 'A' (its second letter) to avoid colliding with "Instrument"'s 'I', which an
/// always-drop-the-first-letter version rendered as a garbled "AA".
func renderMenuBar(_ categories: [MenuCategory]) -> String {
    categories.enumerated().map { index, category in
        if index == openMenuIndex {
            return "\u{1B}[7m \(category.title) \u{1B}[0m"
        }
        guard let range = category.title.range(of: String(category.mnemonic), options: .caseInsensitive) else {
            return " \(category.title) "
        }
        let before = category.title[category.title.startIndex..<range.lowerBound]
        let marked = category.title[range]
        let after = category.title[range.upperBound...]
        return " \(before)\u{1B}[4m\(marked)\u{1B}[0m\(after) "
    }.joined(separator: " ")
}

/// The open dropdown's box, printed inline right under the menu bar (not an absolute-
/// position overlay) — the rest of the frame simply shifts down while a menu is open,
/// which is simpler to keep correct than floating it over fixed content.
func renderDropdown(_ category: MenuCategory) -> [String] {
    let width = (category.items.map(\.label.count).max() ?? 10) + 2
    var lines = ["┌" + String(repeating: "─", count: width) + "┐"]
    for (index, item) in category.items.enumerated() {
        if item.isSeparator {
            if item.label.isEmpty {
                lines.append("├" + String(repeating: "─", count: width) + "┤")
            } else {
                let padded = item.label.padding(toLength: width, withPad: " ", startingAt: 0)
                lines.append("│\u{1B}[2m\(padded)\u{1B}[0m│")
            }
            continue
        }
        let padded = item.label.padding(toLength: width, withPad: " ", startingAt: 0)
        lines.append(index == selectedItemIndex ? "│\u{1B}[7m\(padded)\u{1B}[0m│" : "│\(padded)│")
    }
    lines.append("└" + String(repeating: "─", count: width) + "┘")
    return lines
}
