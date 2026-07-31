import GameKit
import SwiftUI
#if os(iOS)
import UIKit
public typealias PlatformViewController = UIViewController
#elseif os(macOS)
import AppKit
public typealias PlatformViewController = NSViewController
#endif

/// Bridges GameKit's UIKit/AppKit-only authentication and matchmaking UI into this SwiftUI
/// app. `ImprovSession.startGameCenterServer(with:)`/`joinGameCenterSession(with:)` take an
/// already-connected `GKMatch` and know nothing about how it was obtained — everything about
/// GETTING one (signing into Game Center, presenting the invite/auto-match sheet) lives here
/// instead, the same "UI-layer concern, not the session's" split this app already draws
/// around the local-network Bonjour discovery UI (`JamSessionView` itself does the
/// discovering/connecting, `ImprovSession` just takes host/port).
@Observable
@MainActor
final class GameCenterCoordinator: NSObject {
    private(set) var isAuthenticated = false
    var authenticationError: String?
    var matchError: String?
    /// Non-nil while a system-provided view controller (the one-time sign-in sheet, or the
    /// matchmaker/invite sheet) needs presenting — `JamSessionView` observes this and shows
    /// it via `PresentedControllerView` in a `.sheet`.
    private(set) var presentedController: PlatformViewController?

    private var onMatchFound: ((GKMatch) -> Void)?

    /// Safe to call more than once (e.g. every time the Collaboration sub-tab appears) —
    /// re-assigning the same handler is harmless, and this is the ONLY place GameKit's whole
    /// authentication dance is triggered from.
    func authenticateIfNeeded() {
        guard !isAuthenticated else { return }
        GKLocalPlayer.local.authenticateHandler = { [weak self] viewController, error in
            guard let self else { return }
            if let viewController {
                self.presentedController = viewController
            } else if let error {
                self.authenticationError = "\(error)"
            } else {
                self.isAuthenticated = GKLocalPlayer.local.isAuthenticated
            }
        }
    }

    /// Presents Apple's own matchmaker sheet — it offers BOTH auto-match and inviting
    /// specific Game Center friends from within the same UI, for either the organizer or a
    /// participant, so this one method covers both roles; the caller (`JamSessionView`)
    /// decides what to do with the resulting `GKMatch` (`startGameCenterServer`/
    /// `joinGameCenterSession`).
    func presentMatchmaker(minPlayers: Int = 2, maxPlayers: Int = 4, onMatchFound: @escaping (GKMatch) -> Void) {
        guard isAuthenticated else {
            matchError = "Connecte-toi a Game Center d'abord."
            return
        }
        self.onMatchFound = onMatchFound
        matchError = nil
        let request = GKMatchRequest()
        request.minPlayers = minPlayers
        request.maxPlayers = maxPlayers
        guard let controller = GKMatchmakerViewController(matchRequest: request) else {
            matchError = "Game Center indisponible."
            return
        }
        controller.matchmakerDelegate = self
        presentedController = controller
    }

    /// Called by `PresentedControllerView` when the user dismisses a sheet without GameKit
    /// itself having already cleared `presentedController` (e.g. swiping away the auth
    /// sheet) — keeps the two in sync either way.
    func dismissPresentedController() {
        presentedController = nil
    }
}

// `@preconcurrency`: `GKMatchmakerViewControllerDelegate`'s requirements aren't `@MainActor` in
// the SDK (GameKit predates Swift concurrency annotations), even though GameKit always calls
// them on the main thread — this tells the compiler to trust that instead of treating this
// (now `@MainActor`) coordinator's conformance as an isolation-crossing data race risk.
extension GameCenterCoordinator: @preconcurrency GKMatchmakerViewControllerDelegate {
    func matchmakerViewControllerWasCancelled(_ viewController: GKMatchmakerViewController) {
        presentedController = nil
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFailWithError error: Error) {
        matchError = "\(error)"
        presentedController = nil
    }

    func matchmakerViewController(_ viewController: GKMatchmakerViewController, didFind match: GKMatch) {
        presentedController = nil
        onMatchFound?(match)
    }
}

/// Presents an already-created platform view controller (from `GameCenterCoordinator`) inside
/// SwiftUI — GameKit's authentication and matchmaker sheets are UIKit/AppKit-only, there's no
/// SwiftUI-native equivalent.
#if os(iOS)
struct PresentedControllerView: UIViewControllerRepresentable {
    let controller: UIViewController
    func makeUIViewController(context: Context) -> UIViewController { controller }
    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}
}
#elseif os(macOS)
struct PresentedControllerView: NSViewControllerRepresentable {
    let controller: NSViewController
    func makeNSViewController(context: Context) -> NSViewController { controller }
    func updateNSViewController(_ nsViewController: NSViewController, context: Context) {}
}
#endif
