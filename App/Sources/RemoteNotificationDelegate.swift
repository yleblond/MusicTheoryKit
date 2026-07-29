#if os(iOS)
import UIKit

/// Registers for silent remote push at launch so CloudKit can wake this app to merge changes
/// from another device instead of only syncing on a schedule/next foreground. There's nothing
/// else to do here on receipt — SwiftData's CloudKit integration merges the change into
/// `ImprovSession.modelContainer`'s store automatically once the push arrives; that merge is
/// what posts `.NSPersistentStoreRemoteChange`, which `ImprovSession.
/// startObservingRemoteStoreChanges()` is what actually reacts to.
final class RemoteNotificationDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        application.registerForRemoteNotifications()
        return true
    }

    func application(_ application: UIApplication, didReceiveRemoteNotification userInfo: [AnyHashable: Any], fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void) {
        completionHandler(.newData)
    }
}
#elseif os(macOS)
import AppKit

/// macOS counterpart of the iOS `RemoteNotificationDelegate` above — same rationale.
final class RemoteNotificationDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }

    func application(_ application: NSApplication, didReceiveRemoteNotification userInfo: [String: Any]) {}
}
#endif
