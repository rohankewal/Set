import Foundation
import UserNotifications

/// A single local notification fires when rest ends, so the phone can go in a
/// pocket between sets. Authorisation is requested lazily — only if the feature
/// is actually switched on.
@MainActor
enum RestAlerts {
    private static let identifier = "set.rest.finished"
    private static var didRequestAuthorisation = false

    static func requestAuthorisationIfNeeded() async {
        guard !didRequestAuthorisation else { return }
        didRequestAuthorisation = true
        _ = try? await UNUserNotificationCenter.current()
            .requestAuthorization(options: [.alert, .sound])
    }

    static func schedule(in seconds: TimeInterval, exercise: String) async {
        guard seconds > 1 else { return }
        await requestAuthorisationIfNeeded()
        cancel()

        let content = UNMutableNotificationContent()
        content.title = "Rest complete"
        content.body = exercise.isEmpty ? "Next set." : "Next set — \(exercise)."
        content.sound = .default
        content.interruptionLevel = .active

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
        )
        try? await UNUserNotificationCenter.current().add(request)
    }

    static func cancel() {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
