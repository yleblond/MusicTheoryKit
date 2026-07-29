import SwiftUI

@main
struct JamShackApp: App {
    #if os(iOS)
    @UIApplicationDelegateAdaptor(RemoteNotificationDelegate.self) private var appDelegate
    #elseif os(macOS)
    @NSApplicationDelegateAdaptor(RemoteNotificationDelegate.self) private var appDelegate
    #endif

    var body: some Scene {
        WindowGroup {
            ContentView()
                .preferredColorScheme(.dark)
        }
    }
}
