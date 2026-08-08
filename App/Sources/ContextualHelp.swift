import SwiftUI

extension View {
    /// Registers `content` as the CURRENT screen's own contextual help whenever `isActive` is
    /// true — shown by `ContentView`'s shared bottom-bar "?" button instead of a per-screen one
    /// (per explicit request, to reclaim the space every screen's own top-right "?" used to
    /// take). Driven by an explicit `isActive` flag rather than `.onAppear`/`.onDisappear` — tab
    /// content stays mounted across tab switches in this app (see `SoundsView.isActive`'s own
    /// doc comment for the bug that already taught us this), so those never fire on a tab
    /// switch. `id` must be stable and unique to the calling screen, so a rapid switch between
    /// two screens that both register help can't have the outgoing one's `false` transition
    /// clear the incoming one's already-registered content (ordering between the two isn't
    /// guaranteed) — see `AppModel.clearContextualHelp`'s own doc comment.
    func registerContextualHelp(id: String, isActive: Bool, @ViewBuilder content: @escaping () -> some View) -> some View {
        modifier(ContextualHelpRegistration(id: id, isActive: isActive, content: content))
    }
}

private struct ContextualHelpRegistration<HelpContent: View>: ViewModifier {
    @Environment(AppModel.self) private var appModel
    let id: String
    let isActive: Bool
    let content: () -> HelpContent

    func body(content base: Content) -> some View {
        base.onChange(of: isActive, initial: true) { _, active in
            if active {
                appModel.setContextualHelp(id: id, content: content)
            } else {
                appModel.clearContextualHelp(id: id)
            }
        }
    }
}
