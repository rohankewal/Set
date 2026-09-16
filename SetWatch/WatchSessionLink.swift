import Foundation
import Observation
import WatchConnectivity

/// The watch half of the link. Holds the latest snapshot from the phone and
/// sends intents back. It deliberately keeps no state of its own beyond the last
/// snapshot — the phone is the single source of truth for what was logged.
@Observable
final class WatchSessionLink: NSObject, WCSessionDelegate {
    private(set) var snapshot = WatchLink.Snapshot()
    private(set) var isReachable = false
    /// Set briefly after a command so the UI can confirm the tap landed.
    private(set) var lastCommandAt: Date?

    override init() {
        super.init()
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    func send(_ command: WatchLink.Command) {
        lastCommandAt = .now
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        if session.isReachable {
            session.sendMessage(WatchLink.encode(command), replyHandler: { [weak self] reply in
                guard let snapshot = WatchLink.decodeSnapshot(reply) else { return }
                Task { @MainActor in self?.apply(snapshot) }
            })
        } else {
            // The phone is asleep or out of range: queue it rather than drop it.
            session.transferUserInfo(WatchLink.encode(command))
        }
    }

    @MainActor
    private func apply(_ snapshot: WatchLink.Snapshot) {
        self.snapshot = snapshot
    }

    // MARK: WCSessionDelegate

    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            self.send(.requestSnapshot)
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            if reachable { self.send(.requestSnapshot) }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        guard let snapshot = WatchLink.decodeSnapshot(context) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        guard let snapshot = WatchLink.decodeSnapshot(message) else { return }
        Task { @MainActor in self.apply(snapshot) }
    }
}
