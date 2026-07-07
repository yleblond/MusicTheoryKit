import Foundation
import Network

/// One server found on the local network via Bonjour/mDNS — `endpoint` is opaque (an
/// `NWEndpoint.service`), meant to be handed straight to `NetworkClient.connect(to:)`
/// rather than inspected; `name` is what a human picks it out by.
public struct DiscoveredServer: Sendable {
    public let name: String
    public let endpoint: NWEndpoint
}

/// Finds every `NetworkServer` currently advertising itself on the local network (see
/// `NetworkServer.start(port:advertisedAs:)`) — a thin wrapper over `NWBrowser`.
public enum ServiceBrowser {
    /// Both sides of a discoverable session must agree on this — kept private to
    /// `NetworkServer`'s advertising and this browser's searching, never exposed as
    /// something a caller could get wrong by typing it differently.
    static let serviceType = "_musicimprov._tcp"

    /// Blocks the calling thread for up to `timeout` seconds while Bonjour discovers
    /// servers, then returns whatever was found (possibly empty — no server visible isn't
    /// an error). A synchronous bridge over `NWBrowser`'s callback API, the same pattern
    /// `LLMProvider` already uses to bridge `URLSession` into this app's synchronous,
    /// blocking-`readLine()` CLI call style — there's no live-updating list here, just one
    /// snapshot after a fixed search window.
    public static func discover(timeout: TimeInterval) -> [DiscoveredServer] {
        let lock = NSLock()
        // `nonisolated(unsafe)`: mutated only under `lock`, from the browser's callback
        // (an arbitrary queue) and read after `semaphore.wait()` — the lock is the actual
        // safety, this just tells the compiler to trust it instead of inferring a race.
        nonisolated(unsafe) var results: [DiscoveredServer] = []

        let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: .tcp)
        browser.browseResultsChangedHandler = { browseResults, _ in
            let found = browseResults.compactMap { result -> DiscoveredServer? in
                guard case .service(let name, _, _, _) = result.endpoint else { return nil }
                return DiscoveredServer(name: name, endpoint: result.endpoint)
            }
            lock.lock()
            results = found
            lock.unlock()
        }
        browser.start(queue: .global())

        let semaphore = DispatchSemaphore(value: 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { semaphore.signal() }
        semaphore.wait()
        browser.cancel()

        lock.lock()
        defer { lock.unlock() }
        return results
    }
}
