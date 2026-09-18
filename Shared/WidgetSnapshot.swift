import Foundation

/// Everything the home screen and Lock Screen widgets know about. The app
/// writes it into the shared App Group whenever something they show changes;
/// the widget extension only ever reads it. The extension never opens the
/// SwiftData store, which syncs through CloudKit and belongs to the app alone.
///
/// Dated facts are stored rather than finished numbers, so a widget rendered on
/// Monday morning from a snapshot written on Sunday night still says "0 this
/// week" instead of repeating last week's count.
nonisolated struct WidgetSnapshot: Codable, Equatable, Sendable {
    nonisolated struct Session: Codable, Equatable, Sendable {
        var title: String
        var startedAt: Date
        var duration: TimeInterval
        var sets: Int
        var volumeKg: Double
    }

    nonisolated struct Live: Codable, Equatable, Sendable {
        var title: String
        var startedAt: Date
        var setsLogged: Int
    }

    nonisolated struct Record: Codable, Equatable, Sendable {
        /// Already formatted in the athlete's unit, e.g. "Back Squat · 140 kg".
        var headline: String
        /// "Heaviest set", "Week streak"…
        var label: String
        var achievedAt: Date
    }

    var athleteName: String
    var initials: String
    /// Raw `WeightUnit` value.
    var unit: String
    /// The app is behind Face ID, so widgets show that rather than the log.
    var isLocked: Bool
    /// Completed sessions from the last ~20 weeks, newest first.
    var recent: [Session]
    /// Start of every day ever trained, so a streak of any length can be counted.
    var trainedDays: [Date]
    var live: Live?
    var latestRecord: Record?
}

// MARK: - Store

// iOS only: the watch compiles `Shared/` too, but has no widgets, no App Group,
// and so no business touching shared defaults (which would also oblige it to
// declare a reason for them in its privacy manifest).
#if os(iOS)
nonisolated enum WidgetStore {
    static let appGroup = "group.com.rohankewalramani.Set"
    private static let key = "widget.snapshot.v1"

    private static var defaults: UserDefaults? { UserDefaults(suiteName: appGroup) }

    static func read() -> WidgetSnapshot? {
        guard let data = defaults?.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// Returns whether anything changed, so callers only spend the system's
    /// widget reload budget when there is something new to draw.
    @discardableResult
    static func write(_ snapshot: WidgetSnapshot) -> Bool {
        guard let defaults, let data = try? JSONEncoder().encode(snapshot) else { return false }
        guard defaults.data(forKey: key) != data else { return false }
        defaults.set(data, forKey: key)
        return true
    }
}
#endif

nonisolated enum WidgetKind {
    static let week = "SetWeek"
    static let lastWorkout = "SetLastWorkout"
    static let streak = "SetStreak"
}

/// `settracker://workout` opens the live workout; `settracker://start` starts one.
nonisolated enum WidgetRoute {
    static let scheme = "settracker"
    static let workout = URL(string: "settracker://workout")!
    static let start = URL(string: "settracker://start")!
}

// MARK: - Derived

nonisolated extension WidgetSnapshot {
    struct Day: Equatable {
        let date: Date
        let sets: Int
        let isToday: Bool
        let isFuture: Bool
    }

    private func sessions(inWeekOf now: Date, calendar: Calendar) -> [Session] {
        guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return [] }
        return recent.filter { week.contains($0.startedAt) }
    }

    func sessionsThisWeek(now: Date, calendar: Calendar = .current) -> Int {
        sessions(inWeekOf: now, calendar: calendar).count
    }

    func setsThisWeek(now: Date, calendar: Calendar = .current) -> Int {
        sessions(inWeekOf: now, calendar: calendar).reduce(0) { $0 + $1.sets }
    }

    func volumeThisWeek(now: Date, calendar: Calendar = .current) -> Double {
        sessions(inWeekOf: now, calendar: calendar).reduce(0) { $0 + $1.volumeKg }
    }

    /// The seven days of the current week, in the calendar's own order.
    func week(now: Date, calendar: Calendar = .current) -> [Day] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return days(from: start, count: 7, now: now, calendar: calendar)
    }

    /// Weeks of days, oldest first, Monday-aligned like the app's consistency grid.
    func grid(weeks: Int, now: Date, calendar: Calendar = .current) -> [[Day]] {
        var calendar = calendar
        calendar.firstWeekday = 2
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start,
              let start = calendar.date(byAdding: .weekOfYear, value: -(weeks - 1), to: thisWeek)
        else { return [] }
        let flat = days(from: start, count: weeks * 7, now: now, calendar: calendar)
        return stride(from: 0, to: flat.count, by: 7).map { Array(flat[$0..<min($0 + 7, flat.count)]) }
    }

    private func days(from start: Date, count: Int, now: Date, calendar: Calendar) -> [Day] {
        let today = calendar.startOfDay(for: now)
        var sets: [Date: Int] = [:]
        for session in recent {
            sets[calendar.startOfDay(for: session.startedAt), default: 0] += session.sets
        }
        return (0..<count).compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: offset, to: start) else { return nil }
            return Day(
                date: date,
                sets: date > today ? 0 : (sets[date] ?? 0),
                isToday: date == today,
                isFuture: date > today
            )
        }
    }

    /// Tonnage per week, oldest first, ending with the current week.
    func weeklyVolume(weeks: Int, now: Date, calendar: Calendar = .current) -> [Double] {
        guard let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return [] }
        return (0..<weeks).reversed().map { back in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: thisWeek),
                  let week = calendar.dateInterval(of: .weekOfYear, for: start) else { return 0 }
            return recent.filter { week.contains($0.startedAt) }.reduce(0) { $0 + $1.volumeKg }
        }
    }

    /// Same rule as `Stats.weekStreak`: consecutive trained weeks counting back,
    /// where this week not being logged yet doesn't break a live streak.
    func weekStreak(now: Date, calendar: Calendar = .current) -> Int {
        let weeks = Set(trainedDays.compactMap { calendar.dateInterval(of: .weekOfYear, for: $0)?.start })
        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: now)?.start else { return 0 }
        if !weeks.contains(cursor), let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) {
            cursor = previous
        }
        var streak = 0
        while weeks.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = previous
        }
        return streak
    }
}

// MARK: - Sample

nonisolated extension WidgetSnapshot {
    /// What the widget gallery shows before the app has written anything.
    static var sample: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        let titles = ["Push", "Legs", "Pull", "Upper", "Lower"]
        var recent: [Session] = []
        var offset = 1
        while offset < 120 {
            if let day = calendar.date(byAdding: .day, value: -offset, to: today),
               let start = calendar.date(byAdding: .hour, value: 18, to: day) {
                let sets = 14 + (offset * 7) % 9
                recent.append(Session(
                    title: titles[offset % titles.count],
                    startedAt: start,
                    duration: 3_600 + Double((offset * 13) % 20) * 60,
                    sets: sets,
                    volumeKg: Double(sets) * (380 + Double((offset * 31) % 140))
                ))
            }
            offset += offset % 3 == 0 ? 3 : 2
        }
        return WidgetSnapshot(
            athleteName: "You",
            initials: "Y",
            unit: "kilograms",
            isLocked: false,
            recent: recent,
            trainedDays: recent.map { calendar.startOfDay(for: $0.startedAt) },
            live: nil,
            latestRecord: Record(
                headline: "Back Squat · 140 kg",
                label: "Heaviest set",
                achievedAt: recent.first?.startedAt ?? today
            )
        )
    }
}
