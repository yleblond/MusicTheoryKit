import SwiftUI
import WebKit
import ScoreImport

#if canImport(UIKit)
import UIKit
#endif

/// A tap on a rendered note/rest, forwarded from the JS side (`bridge.js`'s `postNoteAction`).
/// `pitches` is empty for a rest. `action` is currently always `"tap"` — a string (not an enum)
/// so future actions (e.g. "play-from-here") don't require a JS/Swift version lockstep.
public struct NoteAction: Equatable, Sendable {
    public let noteID: String
    public let action: String
    public let pitches: [Int]
}

/// Renders a `NotatedScore` as real music notation via VexFlow, hosted in a `WKWebView` (see
/// the score-import plan's rationale for choosing this over extending `ChordStaffView`'s
/// single-column `Canvas` model: rhythm notation — beams, rests, ties — and per-note click
/// handling come from VexFlow essentially for free). Vendored HTML/JS lives in
/// `Resources/ScoreEngraving`; this view only serializes `score` across the bridge and
/// deserializes note taps coming back.
public struct ScoreEngravingView: View {
    public let score: NotatedScore
    public let onNoteAction: ((NoteAction) -> Void)?
    /// Pitches to draw a highlight halo behind, right now — driven by
    /// `ImprovSession.playbackHeldPitches` during playback (see `window.highlightPitches` in
    /// `bridge.js`). Empty (the default) draws no highlight at all.
    public let highlightedPitches: Set<Int>
    /// The elapsed playback position (seconds), driven by `ImprovSession.playbackElapsedSeconds`
    /// — paired with `highlightedPitches` so `bridge.js` can tell "the note sounding right now"
    /// apart from another occurrence of the same pitch elsewhere in the piece (e.g. a repeating
    /// arpeggiated accompaniment, where the same pitch recurs many times).
    public let elapsedSeconds: Double

    public init(score: NotatedScore, highlightedPitches: Set<Int> = [], elapsedSeconds: Double = 0, onNoteAction: ((NoteAction) -> Void)? = nil) {
        self.score = score
        self.highlightedPitches = highlightedPitches
        self.elapsedSeconds = elapsedSeconds
        self.onNoteAction = onNoteAction
    }

    /// Convenience for the common "just imported a raw file, show it as-is" case — builds the
    /// notated model via `ScoreEngravingAdapter` (no role-coloring; that comes from a `Piece`
    /// later, once quantization/analysis exist).
    public init(rawScore: RawScore, highlightedPitches: Set<Int> = [], onNoteAction: ((NoteAction) -> Void)? = nil) {
        self.init(score: ScoreEngravingAdapter.build(from: rawScore), highlightedPitches: highlightedPitches, onNoteAction: onNoteAction)
    }

    public var body: some View {
        ScoreEngravingWebView(score: score, highlightedPitches: highlightedPitches, elapsedSeconds: elapsedSeconds, onNoteAction: onNoteAction)
    }
}

#if canImport(UIKit)
private struct ScoreEngravingWebView: UIViewRepresentable {
    let score: NotatedScore
    let highlightedPitches: Set<Int>
    let elapsedSeconds: Double
    let onNoteAction: ((NoteAction) -> Void)?

    func makeCoordinator() -> ScoreEngravingCoordinator { ScoreEngravingCoordinator(onNoteAction: onNoteAction) }
    func makeUIView(context: Context) -> WKWebView { context.coordinator.makeWebView() }
    func updateUIView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(score, in: webView)
        context.coordinator.highlight(highlightedPitches, elapsedSeconds: elapsedSeconds, in: webView)
    }
}
#else
private struct ScoreEngravingWebView: NSViewRepresentable {
    let score: NotatedScore
    let highlightedPitches: Set<Int>
    let elapsedSeconds: Double
    let onNoteAction: ((NoteAction) -> Void)?

    func makeCoordinator() -> ScoreEngravingCoordinator { ScoreEngravingCoordinator(onNoteAction: onNoteAction) }
    func makeNSView(context: Context) -> WKWebView { context.coordinator.makeWebView() }
    func updateNSView(_ webView: WKWebView, context: Context) {
        context.coordinator.render(score, in: webView)
        context.coordinator.highlight(highlightedPitches, elapsedSeconds: elapsedSeconds, in: webView)
    }
}
#endif

/// Owns the `WKWebView`'s lifecycle and the two halves of the bridge: pushing a `NotatedScore`
/// into `window.renderScore` once `score.html` has finished loading (queuing one if it arrives
/// first), and receiving `noteAction` messages posted back from `bridge.js`.
@MainActor
private final class ScoreEngravingCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate {
    private let onNoteAction: ((NoteAction) -> Void)?
    private var isPageLoaded = false
    private var pendingScore: NotatedScore?
    private var currentHighlight: Set<Int> = []
    private var currentElapsedSeconds: Double = 0
    private var lastPushedHighlight: Set<Int>?
    private var lastPushedElapsedSeconds: Double?

    init(onNoteAction: ((NoteAction) -> Void)?) {
        self.onNoteAction = onNoteAction
    }

    func makeWebView() -> WKWebView {
        let userContentController = WKUserContentController()
        userContentController.add(self, name: "noteAction")
        let configuration = WKWebViewConfiguration()
        configuration.userContentController = userContentController

        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = self

        if let url = Bundle.module.url(forResource: "score", withExtension: "html", subdirectory: "ScoreEngraving") {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        }
        return webView
    }

    func render(_ score: NotatedScore, in webView: WKWebView) {
        guard isPageLoaded else {
            pendingScore = score
            return
        }
        push(score, to: webView)
    }

    private func push(_ score: NotatedScore, to webView: WKWebView) {
        guard let data = try? JSONEncoder().encode(score),
              let json = String(data: data, encoding: .utf8) else { return }
        webView.callAsyncJavaScript(
            "window.renderScore(JSON.parse(scoreJSON));",
            arguments: ["scoreJSON": json],
            in: nil, in: .page, completionHandler: nil
        )
    }

    /// Cheap by design — `bridge.js`'s `window.highlightPitches` just toggles a highlight layer,
    /// no re-layout — so this can be called on every note onset/offset during playback without
    /// re-running `renderScore`'s own 3-pass layout. Pushes whenever EITHER `pitches` or
    /// `elapsedSeconds` changes — the same pitch set can recur (a chord held across a repeated
    /// arpeggio note), and `elapsedSeconds` is exactly what lets `bridge.js` tell those apart.
    func highlight(_ pitches: Set<Int>, elapsedSeconds: Double, in webView: WKWebView) {
        currentHighlight = pitches
        currentElapsedSeconds = elapsedSeconds
        guard isPageLoaded, pitches != lastPushedHighlight || elapsedSeconds != lastPushedElapsedSeconds else { return }
        pushHighlight(to: webView)
    }

    private func pushHighlight(to webView: WKWebView) {
        lastPushedHighlight = currentHighlight
        lastPushedElapsedSeconds = currentElapsedSeconds
        let json = (try? JSONEncoder().encode(Array(currentHighlight))).flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
        webView.evaluateJavaScript("window.highlightPitches && window.highlightPitches(\(json), \(currentElapsedSeconds));")
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        isPageLoaded = true
        if let pendingScore {
            push(pendingScore, to: webView)
            self.pendingScore = nil
        }
        pushHighlight(to: webView) // in case pitches were already set before the page finished loading
    }

    // MARK: - WKScriptMessageHandler

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "noteAction",
              let body = message.body as? [String: Any],
              let noteID = body["noteID"] as? String,
              let action = body["action"] as? String else { return }
        let pitches = (body["pitches"] as? [Any])?.compactMap { ($0 as? NSNumber)?.intValue } ?? []
        onNoteAction?(NoteAction(noteID: noteID, action: action, pitches: pitches))
    }
}

#Preview {
    let ticksPerQuarter = 480
    let rawScore = RawScore(
        sourceFormat: .midi,
        divisionsPerQuarterNote: ticksPerQuarter,
        timeSignatureMap: [RawTimeSignatureEvent(tick: 0, beatsPerMeasure: 4, beatUnit: 4)],
        parts: [
            RawPart(id: "0", name: "Melody", notes: [
                RawNote(startTick: 0, durationTicks: 480, pitch: 60),
                RawNote(startTick: 480, durationTicks: 480, pitch: 62),
                RawNote(startTick: 960, durationTicks: 240, pitch: 64),
                RawNote(startTick: 1200, durationTicks: 240, pitch: 65),
                // beat 4 left as a gap -> renders as a rest
                RawNote(startTick: 1920, durationTicks: 960, pitch: 60),
                RawNote(startTick: 1920, durationTicks: 960, pitch: 64),
                RawNote(startTick: 1920, durationTicks: 960, pitch: 67),
            ]),
        ]
    )
    return ScoreEngravingView(rawScore: rawScore) { action in
        print("Tapped note \(action.noteID), pitches \(action.pitches)")
    }
    .frame(height: 160)
    .padding()
}
