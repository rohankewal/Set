import SwiftUI
import WidgetKit

// MARK: - Timeline

struct SnapshotEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

/// Every widget reads the same snapshot. The timeline carries a second entry at
/// midnight so "today" and "this week" are re-derived from the same facts
/// without the app having to run.
struct SnapshotProvider: TimelineProvider {
    func placeholder(in context: Context) -> SnapshotEntry {
        SnapshotEntry(date: .now, snapshot: .sample)
    }

    func getSnapshot(in context: Context, completion: @escaping (SnapshotEntry) -> Void) {
        let stored = WidgetStore.read()
        let hasHistory = stored.map { !$0.recent.isEmpty } ?? false
        // The gallery shows what the widget looks like in use, not an empty state.
        completion(SnapshotEntry(date: .now, snapshot: context.isPreview && !hasHistory ? .sample : stored))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SnapshotEntry>) -> Void) {
        let now = Date.now
        let calendar = Calendar.current
        let snapshot = WidgetStore.read()
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)) ?? now.addingTimeInterval(86_400)
        completion(Timeline(
            entries: [SnapshotEntry(date: now, snapshot: snapshot), SnapshotEntry(date: midnight, snapshot: snapshot)],
            policy: .atEnd
        ))
    }
}

// MARK: - Tone

/// The app's greys, expressed as opacities of a single ink. In full colour they
/// land within a shade of `Ink.secondary`, `tertiary` and `line`; in the tinted
/// and clear home screen styles, where the system recolours anything opaque,
/// they keep their hierarchy instead of all turning into the same flat tint.
struct Tone {
    let ink: Color
    let isFullColor: Bool

    init(_ mode: WidgetRenderingMode) {
        isFullColor = mode == .fullColor
        ink = isFullColor ? Ink.primary : .primary
    }

    var secondary: Color { ink.opacity(0.62) }
    var tertiary: Color { ink.opacity(0.42) }
    var line: Color { ink.opacity(0.14) }
    var faint: Color { ink.opacity(0.22) }
}

private extension View {
    func micro(_ tone: Tone) -> some View {
        font(.system(size: 10, weight: .semibold))
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(tone.tertiary)
            .lineLimit(1)
    }
}

private extension WidgetSnapshot {
    var weightUnit: WeightUnit { WeightUnit(rawValue: unit) ?? .kilograms }
}

// MARK: - Pieces

/// The current week as seven marks: filled when trained, outlined when missed,
/// a faint dot for days still to come.
private struct WeekMarks: View {
    let days: [WidgetSnapshot.Day]
    let tone: Tone
    var mark: CGFloat = 11
    var showsLetters = true

    var body: some View {
        HStack(spacing: 0) {
            ForEach(days, id: \.date) { day in
                VStack(spacing: 5) {
                    ZStack {
                        if day.sets > 0 {
                            Circle().fill(tone.ink)
                        } else if day.isFuture {
                            Circle().fill(tone.line).frame(width: mark * 0.36, height: mark * 0.36)
                        } else {
                            Circle().strokeBorder(day.isToday ? tone.secondary : tone.faint, lineWidth: 1)
                        }
                    }
                    .frame(width: mark, height: mark)

                    if showsLetters {
                        Text(day.date.formatted(.dateTime.weekday(.narrow)))
                            .font(.system(size: 9, weight: day.isToday ? .bold : .medium))
                            .foregroundStyle(day.isToday ? tone.secondary : tone.tertiary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Weekly tonnage as a row of bars; the current week is the one in full ink.
private struct VolumeBars: View {
    let values: [Double]
    let tone: Tone

    var body: some View {
        let peak = max(values.max() ?? 0, 1)
        HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(values.enumerated()), id: \.offset) { index, value in
                GeometryReader { proxy in
                    VStack {
                        Spacer(minLength: 0)
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(index == values.count - 1 ? tone.ink : tone.faint)
                            .frame(height: max(3, proxy.size.height * value / peak))
                    }
                }
            }
        }
    }
}

/// Seventeen weeks of marks, the same four steps of grey as the app.
private struct ConsistencyMarks: View {
    let weeks: [[WidgetSnapshot.Day]]
    let tone: Tone

    var body: some View {
        let peak = max(weeks.joined().map(\.sets).max() ?? 1, 1)
        // Sized as one block rather than per cell, so it shrinks to whatever
        // height the widget has left instead of pushing the footer off.
        HStack(spacing: 3) {
            ForEach(Array(weeks.enumerated()), id: \.offset) { _, week in
                VStack(spacing: 3) {
                    ForEach(week, id: \.date) { day in
                        RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                            .fill(fill(day.sets, peak: peak))
                            .overlay {
                                RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                                    .strokeBorder(tone.line, lineWidth: day.sets == 0 && !day.isFuture ? 0.5 : 0)
                            }
                    }
                }
            }
        }
        .aspectRatio(CGFloat(weeks.count) / 7 * 1.03, contentMode: .fit)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func fill(_ sets: Int, peak: Int) -> Color {
        guard sets > 0 else { return .clear }
        switch Double(sets) / Double(peak) {
        case ..<0.34: return tone.ink.opacity(0.28)
        case ..<0.67: return tone.ink.opacity(0.58)
        default: return tone.ink
        }
    }
}

private struct Stat: View {
    let label: String
    let value: String
    var unit: String?
    var size: CGFloat = 22
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).micro(tone)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.readout(size))
                    .readoutTracking(size)
                    .foregroundStyle(tone.ink)
                if let unit {
                    Text(unit)
                        .font(.system(size: size * 0.5, weight: .medium))
                        .foregroundStyle(tone.tertiary)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shown until the app has written a snapshot, and whenever it's locked.
private struct Placeholder: View {
    let symbol: String
    let title: String
    let detail: String
    let tone: Tone

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: symbol)
                .font(.system(size: 17, weight: .regular))
                .foregroundStyle(tone.ink)
            Spacer(minLength: 0)
            Text(title)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tone.ink)
            Text(detail)
                .font(.system(size: 12))
                .foregroundStyle(tone.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Resolves the three states every widget has before it draws any data.
private struct SnapshotGate<Content: View>: View {
    let entry: SnapshotEntry
    let tone: Tone
    @ViewBuilder let content: (WidgetSnapshot) -> Content

    var body: some View {
        if let snapshot = entry.snapshot {
            if snapshot.isLocked {
                Placeholder(symbol: "lock", title: "Set is locked", detail: "Your log stays in the app.", tone: tone)
            } else {
                content(snapshot)
            }
        } else {
            Placeholder(symbol: "circle.hexagongrid", title: "Nothing yet", detail: "Open Set to log a workout.", tone: tone)
        }
    }
}

// MARK: - This week

struct WeekWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let tone = Tone(mode)
        SnapshotGate(entry: entry, tone: tone) { snapshot in
            switch family {
            case .systemMedium: medium(snapshot, tone)
            case .systemLarge: large(snapshot, tone)
            default: small(snapshot, tone)
            }
        }
    }

    private func count(_ snapshot: WidgetSnapshot, _ tone: Tone, size: CGFloat) -> some View {
        let sessions = snapshot.sessionsThisWeek(now: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            Text("\(sessions)")
                .font(.readout(size))
                .readoutTracking(size)
                .foregroundStyle(tone.ink)
                .contentTransition(.numericText())
            Text(sessions == 1 ? "session" : "sessions")
                .font(.system(size: 13))
                .foregroundStyle(tone.secondary)
        }
    }

    private func small(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        let streak = snapshot.weekStreak(now: entry.date)
        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("This week").micro(tone)
                Spacer(minLength: 4)
                if streak > 1 {
                    Text("\(streak) wk").micro(tone).monospacedDigit()
                }
            }
            Spacer(minLength: 2)
            count(snapshot, tone, size: 46)
            Spacer(minLength: 8)
            WeekMarks(days: snapshot.week(now: entry.date), tone: tone, mark: 10)
        }
    }

    private func medium(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        let unit = snapshot.weightUnit
        let streak = snapshot.weekStreak(now: entry.date)
        return HStack(spacing: 18) {
            VStack(alignment: .leading, spacing: 0) {
                Text("This week").micro(tone)
                Spacer(minLength: 2)
                count(snapshot, tone, size: 46)
                Spacer(minLength: 8)
                WeekMarks(days: snapshot.week(now: entry.date), tone: tone, mark: 10)
            }
            .frame(maxWidth: .infinity)

            Rectangle().fill(tone.line).frame(width: 0.5)

            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("8 weeks").micro(tone)
                    Spacer(minLength: 4)
                    if streak > 1 {
                        Text("\(streak) wk").micro(tone).monospacedDigit()
                    }
                }
                VolumeBars(values: snapshot.weeklyVolume(weeks: 8, now: entry.date), tone: tone)
                HStack(spacing: 8) {
                    Stat(label: "Sets", value: "\(snapshot.setsThisWeek(now: entry.date))", size: 18, tone: tone)
                    Stat(
                        label: "Volume",
                        value: Format.volume(snapshot.volumeThisWeek(now: entry.date), in: unit),
                        unit: unit.short,
                        size: 18,
                        tone: tone
                    )
                }
            }
            .frame(maxWidth: .infinity)
        }
    }

    private func large(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        let unit = snapshot.weightUnit
        return VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(entry.date.formatted(.dateTime.weekday(.wide).day().month(.wide))).micro(tone)
                    Text("Set")
                        .font(.system(size: 24, weight: .semibold))
                        .tracking(-0.6)
                        .foregroundStyle(tone.ink)
                }
                Spacer()
                let streak = snapshot.weekStreak(now: entry.date)
                if streak > 1 {
                    Text("\(streak) wk streak").micro(tone).monospacedDigit()
                }
            }

            Spacer(minLength: 12)

            HStack(spacing: 8) {
                Stat(label: "Sessions", value: "\(snapshot.sessionsThisWeek(now: entry.date))", tone: tone)
                Stat(label: "Sets", value: "\(snapshot.setsThisWeek(now: entry.date))", tone: tone)
                Stat(
                    label: "Volume",
                    value: Format.volume(snapshot.volumeThisWeek(now: entry.date), in: unit),
                    unit: unit.short,
                    tone: tone
                )
            }

            Spacer(minLength: 14)

            ConsistencyMarks(weeks: snapshot.grid(weeks: 17, now: entry.date), tone: tone)

            Spacer(minLength: 14)
            Rectangle().fill(tone.line).frame(height: 0.5)
            Spacer(minLength: 12)

            footer(snapshot, tone)
        }
    }

    @ViewBuilder
    private func footer(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        HStack(alignment: .top, spacing: 12) {
            if let last = snapshot.recent.first {
                VStack(alignment: .leading, spacing: 3) {
                    Text("Last · \(Format.relativeDay(last.startedAt))").micro(tone)
                    Text(last.title)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tone.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if let record = snapshot.latestRecord {
                VStack(alignment: .leading, spacing: 3) {
                    Text(record.label).micro(tone)
                    Text(record.headline)
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(tone.ink)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }
}

// MARK: - Last workout

struct LastWorkoutWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var mode

    var body: some View {
        let tone = Tone(mode)
        SnapshotGate(entry: entry, tone: tone) { snapshot in
            Group {
                if family == .systemMedium {
                    HStack(spacing: 18) {
                        primary(snapshot, tone).frame(maxWidth: .infinity, alignment: .leading)
                        Rectangle().fill(tone.line).frame(width: 0.5)
                        secondary(snapshot, tone).frame(maxWidth: .infinity)
                    }
                } else {
                    primary(snapshot, tone)
                }
            }
            .widgetURL(snapshot.live != nil ? WidgetRoute.workout : (snapshot.recent.isEmpty ? WidgetRoute.start : nil))
        }
    }

    @ViewBuilder
    private func primary(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        let unit = snapshot.weightUnit
        VStack(alignment: .leading, spacing: 0) {
            if let live = snapshot.live {
                HStack(spacing: 5) {
                    Circle().fill(tone.ink).frame(width: 5, height: 5)
                    Text("In progress").micro(tone)
                }
                Text(live.title)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(tone.ink)
                    .lineLimit(2)
                    .padding(.top, 4)
                Spacer(minLength: 4)
                Text(live.startedAt, style: .timer)
                    .font(.readout(30))
                    .readoutTracking(30)
                    .foregroundStyle(tone.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("^[\(live.setsLogged) set](inflect: true) logged")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(tone.tertiary)
            } else if let last = snapshot.recent.first {
                Text(Format.relativeDay(last.startedAt)).micro(tone)
                Text(last.title)
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(tone.ink)
                    .lineLimit(2)
                    .padding(.top, 4)
                Spacer(minLength: 4)
                HStack(alignment: .firstTextBaseline, spacing: 3) {
                    Text("\(last.sets)")
                        .font(.readout(34))
                        .readoutTracking(34)
                        .foregroundStyle(tone.ink)
                    Text(last.sets == 1 ? "set" : "sets")
                        .font(.system(size: 13))
                        .foregroundStyle(tone.secondary)
                }
                Text("\(Format.volume(last.volumeKg, in: unit)) \(unit.short) · \(Format.shortDuration(last.duration))")
                    .font(.system(size: 12).monospacedDigit())
                    .foregroundStyle(tone.tertiary)
                    .lineLimit(1)
            } else {
                Placeholder(symbol: "plus", title: "First workout", detail: "Tap to start one.", tone: tone)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func secondary(_ snapshot: WidgetSnapshot, _ tone: Tone) -> some View {
        let unit = snapshot.weightUnit
        VStack(alignment: .leading, spacing: 0) {
            if snapshot.live == nil, let record = snapshot.latestRecord {
                Text(record.label).micro(tone)
                Text(record.headline)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(tone.ink)
                    .lineLimit(2)
                    .padding(.top, 4)
            } else {
                Text("This week").micro(tone)
                Text("^[\(snapshot.sessionsThisWeek(now: entry.date)) session](inflect: true) · \(Format.volume(snapshot.volumeThisWeek(now: entry.date), in: unit)) \(unit.short)")
                    .font(.system(size: 13, weight: .medium).monospacedDigit())
                    .foregroundStyle(tone.ink)
                    .lineLimit(2)
                    .padding(.top, 4)
            }
            Spacer(minLength: 8)
            Link(destination: snapshot.live != nil ? WidgetRoute.workout : WidgetRoute.start) {
                HStack(spacing: 6) {
                    Image(systemName: snapshot.live != nil ? "arrow.forward" : "plus")
                    Text(snapshot.live != nil ? "Resume" : "Start")
                }
                .font(.system(size: 14, weight: .semibold))
                .frame(maxWidth: .infinity)
                .frame(height: 40)
                .foregroundStyle(tone.isFullColor ? Ink.onAccent : tone.ink)
                .background {
                    if tone.isFullColor {
                        Capsule().fill(Ink.accent)
                    } else {
                        Capsule().strokeBorder(tone.secondary, lineWidth: 1)
                    }
                }
            }
        }
    }
}

// MARK: - Lock Screen

struct StreakWidgetView: View {
    let entry: SnapshotEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        let tone = Tone(.accented)
        if let snapshot = entry.snapshot, !snapshot.isLocked {
            let streak = snapshot.weekStreak(now: entry.date)
            let sessions = snapshot.sessionsThisWeek(now: entry.date)
            switch family {
            case .accessoryCircular:
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -1) {
                        Text("\(streak)")
                            .font(.system(size: 22, weight: .semibold).monospacedDigit())
                            .minimumScaleFactor(0.6)
                        Text("WK")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1)
                            .opacity(0.6)
                    }
                }
                .widgetAccentable()
                .accessibilityLabel("\(streak) week streak")
            case .accessoryInline:
                Label {
                    Text("^[\(sessions) session](inflect: true) this week")
                } icon: {
                    Image(systemName: "figure.strengthtraining.traditional")
                }
            default:
                VStack(alignment: .leading, spacing: 3) {
                    ViewThatFits {
                        Text(streak > 1 ? "This week · \(streak) wk streak" : "This week")
                        Text(streak > 1 ? "This week · \(streak) wk" : "This week")
                    }
                    .font(.system(size: 11, weight: .semibold))
                    .textCase(.uppercase)
                    .lineLimit(1)
                    .opacity(0.6)
                    ViewThatFits {
                        Text("^[\(sessions) session](inflect: true) · \(snapshot.setsThisWeek(now: entry.date)) sets")
                        Text("^[\(sessions) session](inflect: true)")
                    }
                    .font(.system(size: 15, weight: .semibold).monospacedDigit())
                    .lineLimit(1)
                    .widgetAccentable()
                    WeekMarks(days: snapshot.week(now: entry.date), tone: tone, mark: 7, showsLetters: false)
                        .padding(.top, 2)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            switch family {
            case .accessoryInline:
                Text(entry.snapshot?.isLocked == true ? "Set is locked" : "Set")
            default:
                ZStack {
                    if family == .accessoryCircular { AccessoryWidgetBackground() }
                    Image(systemName: entry.snapshot?.isLocked == true ? "lock" : "circle.hexagongrid")
                        .font(.system(size: 18, weight: .medium))
                }
            }
        }
    }
}

// MARK: - Configurations

struct WeekWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.week, provider: SnapshotProvider()) { entry in
            WeekWidgetView(entry: entry)
                .containerBackground(Ink.canvas, for: .widget)
        }
        .configurationDisplayName("This Week")
        .description("Sessions, sets and volume so far this week.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct LastWorkoutWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.lastWorkout, provider: SnapshotProvider()) { entry in
            LastWorkoutWidgetView(entry: entry)
                .containerBackground(Ink.canvas, for: .widget)
        }
        .configurationDisplayName("Last Workout")
        .description("Your most recent session, or the one in progress.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}

struct StreakWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: WidgetKind.streak, provider: SnapshotProvider()) { entry in
            StreakWidgetView(entry: entry)
                .containerBackground(.clear, for: .widget)
        }
        .configurationDisplayName("Streak")
        .description("Your week streak and this week's training, on the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

// MARK: - Previews

#Preview("Week", as: .systemSmall) { WeekWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Week", as: .systemMedium) { WeekWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Week", as: .systemLarge) { WeekWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Last", as: .systemSmall) { LastWorkoutWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Last", as: .systemMedium) { LastWorkoutWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
#Preview("Streak", as: .accessoryRectangular) { StreakWidget() } timeline: { SnapshotEntry(date: .now, snapshot: .sample) }
