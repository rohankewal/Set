#if canImport(CloudKit)
import CloudKit
#endif
import Foundation
import Observation
import SwiftData

/// Whether the log is actually being written to disk.
///
/// A workout tracker that silently stops saving is worse than one that crashes:
/// you find out weeks later. Everything that writes reports through here, and
/// anything other than `.healthy` is shown to the user rather than logged.
@Observable
@MainActor
final class StoreHealth {
    static let shared = StoreHealth()

    enum Mode: Equatable {
        /// Normal: a file on disk that survives relaunch.
        case disk
        /// The store couldn't be opened. The app runs, but nothing is kept.
        case memory(reason: String)
    }

    /// Whether the private database is reachable. Sync itself is SwiftData's
    /// job; this only reports whether the account behind it is usable, which is
    /// the part a user can act on.
    enum Sync: Equatable {
        case unknown
        case syncing
        case noAccount
        case restricted
        case unavailable(String)

        var label: String {
            switch self {
            case .unknown: "Checking…"
            case .syncing: "Syncing with iCloud"
            case .noAccount: "Not signed in to iCloud"
            case .restricted: "iCloud restricted on this device"
            case .unavailable: "iCloud unavailable"
            }
        }

        var isWorking: Bool { self == .syncing }
    }

    private(set) var sync: Sync = .unknown
    private(set) var mode: Mode = .disk
    /// Most recent write failure, if any.
    private(set) var lastFailure: String?
    private(set) var failureCount = 0
    private(set) var lastSavedAt: Date?

    var isHealthy: Bool {
        mode == .disk && lastFailure == nil
    }

    /// Sync not working isn't a warning — the log is still safe on the device.
    /// It's stated plainly in Settings and nowhere else.
    /// The sentence a user should read. Plain language, no error codes — those
    /// go in `detail`, one level down in Settings, where they're useful for a
    /// bug report and nowhere else.
    var warning: String? {
        switch mode {
        case .memory:
            return "Not saving to this device. Anything logged now will be lost when the app closes."
        case .disk:
            guard lastFailure != nil else { return nil }
            return failureCount == 1
                ? "The last save didn't go through. Your most recent change may not be kept."
                : "\(failureCount) saves haven't gone through. Recent changes may not be kept."
        }
    }

    /// The technical cause, for the Settings row only.
    var detail: String? {
        switch mode {
        case let .memory(reason): reason
        case .disk: lastFailure
        }
    }

    func reportMemoryFallback(reason: String) {
        mode = .memory(reason: reason)
    }

    /// Checked on launch and on foreground. Cheap, and the answer changes when
    /// the user signs in or out of iCloud without the app running.
    func refreshSyncStatus() async {
        #if canImport(CloudKit)
        guard case .disk = mode else {
            sync = .unavailable("Local store unavailable")
            return
        }
        do {
            switch try await CKContainer(identifier: Self.containerID).accountStatus() {
            case .available: sync = .syncing
            case .noAccount: sync = .noAccount
            case .restricted: sync = .restricted
            case .couldNotDetermine: sync = .unknown
            case .temporarilyUnavailable: sync = .unavailable("Temporarily unavailable")
            @unknown default: sync = .unknown
            }
        } catch {
            sync = .unavailable((error as NSError).localizedDescription)
        }
        #endif
    }

    /// Must match the entitlement; SwiftData resolves the same container from it.
    static let containerID = "iCloud.com.rohankewalramani.Set"

    func recordSuccess() {
        lastSavedAt = .now
        if lastFailure != nil {
            lastFailure = nil
            failureCount = 0
        }
    }

    func record(_ error: Error) {
        failureCount += 1
        lastFailure = (error as NSError).localizedDescription
    }
}

extension ModelContext {
    /// Saves and reports the outcome. Replaces `try? save()`, which threw away
    /// exactly the information worth keeping.
    @MainActor
    @discardableResult
    func saveChanges() -> Bool {
        guard hasChanges else { return true }
        do {
            try save()
            StoreHealth.shared.recordSuccess()
            return true
        } catch {
            StoreHealth.shared.record(error)
            return false
        }
    }
}
