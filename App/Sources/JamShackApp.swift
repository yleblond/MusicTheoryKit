import SwiftUI

@main
struct JamShackApp: App {
    #if os(iOS) || os(visionOS)
    @UIApplicationDelegateAdaptor(RemoteNotificationDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(RemoteNotificationDelegate.self) private var appDelegate
    #endif

    @State private var appModel = AppModel()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)

        // Detachable auxiliary windows (see `AppModel`/`SessionGatedView`) — spatially
        // placeable on visionOS, floating separate windows on macOS. Not offered on iOS,
        // which doesn't support this kind of ad hoc multi-window use well. Each gets the same
        // `.preferredColorScheme(.dark)` as the main window — without it, a plain new
        // `WindowGroup`'s content doesn't pick up the app's dark theme (bars/materials render
        // as flat black instead of the intended vibrant dark styling).
        #if os(macOS) || os(visionOS)
        WindowGroup(id: AuxiliaryWindowID.computerKeyboard.rawValue) {
            ComputerKeyboardWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 900, height: 260)

        WindowGroup(id: AuxiliaryWindowID.runScreen.rawValue) {
            RunScreenWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 1100, height: 700)

        WindowGroup(id: AuxiliaryWindowID.guideLecture.rawValue) {
            GuideLectureWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 1000, height: 700)

        WindowGroup(id: AuxiliaryWindowID.microphone.rawValue) {
            MicrophoneWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 700, height: 620)

        WindowGroup(id: AuxiliaryWindowID.sceneLayout.rawValue) {
            SceneLayoutWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 1000, height: 700)

        WindowGroup(id: AuxiliaryWindowID.theorie.rawValue) {
            TheoryWindow()
                .preferredColorScheme(.dark)
        }
        .environment(appModel)
        .defaultSize(width: 1100, height: 800)
        #endif
    }
}
