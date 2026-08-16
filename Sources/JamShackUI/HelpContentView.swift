import SwiftUI

/// Shared renderer for per-screen contextual help — one authored body string per screen instead
/// of a bespoke SwiftUI struct per screen (see `HelpTopicID` in the App target for the registry
/// this feeds). `body` is parsed via `AttributedString(markdown:)` (native Foundation API, no
/// third-party dependency) with `.inlineOnlyPreservingWhitespace` — confirmed empirically (not
/// guessed) that this mode preserves every `\n` literally rather than collapsing it CommonMark-
/// style (a single `\n` becoming a soft-break space, a blank line vanishing entirely), while still
/// parsing inline emphasis/links. Authoring convention that follows from this: write body text
/// like plain prose — a lone `\n` is its own line break, a blank line (`\n\n`) is a paragraph gap
/// — and use literal "•" characters for anything list-like, since `Text` never applies
/// markdown's BLOCK-level styling (headings, real bullet lists) regardless of parsing mode, only
/// inline emphasis/links. Cross-screen references use `[label](jamshackhelp://<HelpTopicID raw
/// value>)` — a made-up scheme, never actually registered with the OS, intercepted instead by
/// `View.interceptHelpLinks(_:)` wherever this is shown.
public struct HelpContentView<Trailing: View>: View {
    public let title: String
    public let bodyText: String
    private let trailing: () -> Trailing

    public init(title: String, body: String, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.bodyText = body
        self.trailing = trailing
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(.headline)
            Text(attributedBody)
                .font(.callout)
            trailing()
        }
        .frame(maxWidth: 340, alignment: .leading)
    }

    /// Falls back to the raw string if markdown parsing throws — hand-authored prose can contain
    /// an unescaped `[`/`_`/backtick; a typo in help text should never crash the help window.
    private var attributedBody: AttributedString {
        (try? AttributedString(markdown: bodyText, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
            ?? AttributedString(bodyText)
    }
}
