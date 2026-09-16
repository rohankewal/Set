import Foundation
import Observation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// The phone half of the watch link.
///
/// The phone owns the store; this publishes a small snapshot of the live session
/// to the watch and executes the intents it sends back. Everything is funnelled
/// through `WorkoutEngine`, so a set logged on the wrist takes exactly the same
/// path as one logged on the phone — same milestone checks, same rest timer,
/// same save.
@Observable
final class PhoneWatchLink: NSObject {
    @ObservationIgnored weak var engine: WorkoutEngine?
    @ObservationIgnored private var settings: AppSettings?
    private(set) var isPaired = false

    func activate(settings: AppSettings) {
        self.settings = settings
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        #endif
    }

    /// Pushes the current state to the watch. Cheap enough to call after every
    /// mutation; `updateApplicationContext` coalesces automatically.
    func publish() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        let payload = WatchLink.encode(snapshot())
        guard !payload.isEmpty else { return }
        try? session.updateApplicationContext(payload)
        #endif
    }

    @MainActor
    func snapshot() -> WatchLink.Snapshot {
        guard let engine, let settings, let session = engine.session else {
            return WatchLink.Snapshot()
        }

        var snapshot = WatchLink.Snapshot()
        snapshot.isRunning = true
        snapshot.sessionTitle = session.title
        snapshot.startedAt = session.startedAt
        snapshot.setsLogged = session.completedSets.count
        snapshot.restEndsAt = engine.restEndsAt
        snapshot.restRemaining = engine.restRemaining
        snapshot.isRestPaused = engine.isRestPaused

        if let block = engine.focusedBlock, let set = engine.focusedSet {
            snapshot.exercise = block.name
            snapshot.usesWeight = block.tracking.usesWeight
            snapshot.weight = Format.weight(set.weightKg, in: settings.unit)
            snapshot.unit = settings.unit.short
            snapshot.reps = block.tracking == .duration ? set.seconds : set.reps
            snapshot.setNumber = set.index + 1
        }
        return snapshot
    }

    @MainActor
    func handle(_ command: WatchLink.Command) {
        guard let engine else { return }
        switch command {
        case .logSet:
            if let block = engine.focusedBlock, let set = engine.focusedSet {
                engine.toggleCompletion(of: set, in: block)
                if block.orderedSets.allSatisfy(\.isComplete) {
                    engine.addSet(to: block)
                }
            }
        case .skipRest: engine.endRest()
        case .toggleRest: engine.toggleRest()
        case .addFifteen: engine.adjustRest(by: 15)
        case .nextExercise: engine.moveFocus(by: 1)
        case .previousExercise: engine.moveFocus(by: -1)
        case .requestSnapshot: break
        }
        publish()
    }
}

#if canImport(WatchConnectivity)
extension PhoneWatchLink: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith state: WCSessionActivationState,
        error: Error?
    ) {
        let paired = session.isPaired && session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.publish()
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard let command = WatchLink.decodeCommand(message) else {
            replyHandler([:])
            return
        }
        Task { @MainActor in
            self.handle(command)
            replyHandler(WatchLink.encode(self.snapshot()))
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        guard let command = WatchLink.decodeCommand(userInfo) else { return }
        Task { @MainActor in self.handle(command) }
    }
}
#endif
