import SwiftUI

/// Which of a `TheoryLibraryLayout`'s two panes is showing — only meaningful in the compact
/// (push-navigation) mode; ignored when both panes show side by side.
public enum TheoryLibraryScreen {
    case list, detail
}

public enum TheoryLibraryLayoutMode {
    /// macOS/visionOS always get two columns (no meaningful "compact window" concept in this
    /// app, same assumption the rest of the app already makes for auxiliary windows); iOS
    /// (which covers both iPhone and iPad — there's no separate `os(iPadOS)`) distinguishes via
    /// `horizontalSizeClass`: `.compact` on iPhone/narrow split view, `.regular` on a
    /// full-width iPad. Exposed as a standalone function (not just `TheoryLibraryLayout`'s own
    /// private computed property) so a screen's own list column can make the SAME call for a
    /// secondary decision (e.g. a picker style), without duplicating this logic.
    public static func usesTwoColumns(horizontalSizeClass: UserInterfaceSizeClass?) -> Bool {
        #if os(macOS) || os(visionOS)
        true
        #else
        horizontalSizeClass != .compact
        #endif
    }
}

/// Shared adaptive layout for the Chord/Mode/Progression Library screens: side-by-side columns
/// on macOS/visionOS and iPad-width iOS, or the original push list→detail navigation on
/// iPhone-width iOS — one component so this size-class decision isn't duplicated 3 times.
///
/// `detailContent` receives `(showBackButton, onBack)`: `true`/a working callback in the
/// compact case (there's somewhere to go back to), `false`/a no-op when both panes are already
/// visible side by side (nothing to "go back" from).
public struct TheoryLibraryLayout<ListContent: View, DetailContent: View>: View {
    @Binding var screen: TheoryLibraryScreen
    let sidebarWidth: CGFloat
    @ViewBuilder let listContent: () -> ListContent
    @ViewBuilder let detailContent: (_ showBackButton: Bool, _ onBack: @escaping () -> Void) -> DetailContent

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    public init(
        screen: Binding<TheoryLibraryScreen>,
        sidebarWidth: CGFloat = 320,
        @ViewBuilder listContent: @escaping () -> ListContent,
        @ViewBuilder detailContent: @escaping (_ showBackButton: Bool, _ onBack: @escaping () -> Void) -> DetailContent
    ) {
        self._screen = screen
        self.sidebarWidth = sidebarWidth
        self.listContent = listContent
        self.detailContent = detailContent
    }

    private var usesTwoColumns: Bool {
        TheoryLibraryLayoutMode.usesTwoColumns(horizontalSizeClass: horizontalSizeClass)
    }

    public var body: some View {
        if usesTwoColumns {
            HStack(spacing: 0) {
                listContent()
                    .frame(width: sidebarWidth)
                Divider()
                detailContent(false, {})
            }
        } else {
            switch screen {
            case .list: listContent()
            case .detail: detailContent(true, { screen = .list })
            }
        }
    }
}
