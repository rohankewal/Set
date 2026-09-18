import Foundation
import WidgetKit

/// Writes what the widgets show into the App Group. Cheap enough to call on
/// every lifecycle change: the snapshot is only written, and timelines only
/// reloaded, when it actually differs from the last one.
@MainActor
enum WidgetPublisher {
    /// Long enough for the 17-week grid and the 8-week bars, with a margin.
    private static let recentWindowDays = 20 * 7

    static func publish(athlete: Athlete?, engine: WorkoutEngine, settings: AppSettings) {
        let calendar = Calendar.current
        let sessions = athlete?.completedSessions ?? []
        let cutoff = calendar.date(byAdding: .day, value: -recentWindowDays, to: .now) ?? .distantPast

        let recent = sessions
            .prefix { $0.startedAt >= cutoff }
            .map {
                WidgetSnapshot.Session(
                    title: $0.title,
                    startedAt: $0.startedAt,
                    duration: $0.duration,
                    sets: $0.workingSets.count,
                    volumeKg: $0.volumeKg
                )
            }

        let trainedDays = Set(sessions.map { calendar.startOfDay(for: $0.startedAt) }).sorted(by: >)

        let live = engine.session.map {
            WidgetSnapshot.Live(title: $0.title, startedAt: $0.startedAt, setsLogged: $0.completedSets.count)
        }

        let record = athlete?.allMilestones
            .filter { $0.previousValue > 0 || !$0.kind.isExerciseScoped }
            .max { $0.achievedAt < $1.achievedAt }
            .map {
                WidgetSnapshot.Record(
                    headline: MilestoneFormatter.headline(for: $0, unit: settings.unit),
                    label: $0.kind.label,
                    achievedAt: $0.achievedAt
                )
            }

        let snapshot = WidgetSnapshot(
            athleteName: athlete?.name ?? "",
            initials: athlete?.initials ?? "",
            unit: settings.unit.rawValue,
            isLocked: settings.requireBiometrics,
            recent: Array(recent),
            trainedDays: trainedDays,
            live: live,
            latestRecord: record
        )

        if WidgetStore.write(snapshot) {
            WidgetCenter.shared.reloadAllTimelines()
        }
    }
}
