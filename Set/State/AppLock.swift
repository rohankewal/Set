import Foundation
import LocalAuthentication
import Observation

/// Optional Face ID / passcode gate. Training logs are personal data: when the
/// gate is on, nothing is rendered until the device owner is verified, and the
/// app re-locks as soon as it leaves the foreground.
@Observable
final class AppLock {
    private(set) var isLocked: Bool
    private(set) var lastError: String?
    @ObservationIgnored private let settings: AppSettings

    init(settings: AppSettings) {
        self.settings = settings
        self.isLocked = settings.requireBiometrics
    }

    var biometryLabel: String {
        let context = LAContext()
        _ = context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: nil)
        switch context.biometryType {
        case .faceID: return "Face ID"
        case .touchID: return "Touch ID"
        case .opticID: return "Optic ID"
        default: return "Device passcode"
        }
    }

    var isAvailable: Bool {
        LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: nil)
    }

    func lockIfNeeded() {
        if settings.requireBiometrics { isLocked = true }
    }

    func refreshRequirement() {
        isLocked = settings.requireBiometrics ? isLocked : false
    }

    func unlock() async {
        guard settings.requireBiometrics else { isLocked = false; return }
        let context = LAContext()
        context.localizedFallbackTitle = "Use Passcode"
        do {
            let success = try await context.evaluatePolicy(
                .deviceOwnerAuthentication,
                localizedReason: "Unlock your training log"
            )
            isLocked = !success
            lastError = nil
        } catch {
            isLocked = true
            lastError = (error as? LAError)?.localizedDescription ?? error.localizedDescription
        }
    }
}
