import SwiftData
import SwiftUI

struct MilestonesView: View {
    let athlete: Athlete?
    @Environment(AppSettings.self) private var settings

    /// Only surfaced records — the silent "first entry" baselines are filtered out.
    private var milestones: [Milestone] {
        (athlete?.allMilestones ?? [])
            .filter { $0.previousValue > 0 || !$0.kind.isExerciseScoped }
            .sorted { $0.achievedAt > $1.achievedAt }
    }

    private var grouped: [(String, [Milestone])] {
        let calendar = Calendar.current
        return Dictionary(grouping: milestones) { milestone -> Date in
            calendar.date(from: calendar.dateComponents([.year, .month], from: milestone.achievedAt)) ?? milestone.achievedAt
        }
        .sorted { $0.key > $1.key }
        .map { ($0.key.formatted(.dateTime.month(.wide).year()), $0.value) }
    }

    var body: some View {
        Screen {
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    if milestones.isEmpty {
                        EmptyState(
                            symbol: "trophy",
                            title: "No milestones yet",
                            message: "Beat a previous best and it lands here automatically — no goals to set up first."
                        )
                    }

                    ForEach(grouped, id: \.0) { month, items in
                        VStack(alignment: .leading, spacing: 10) {
                            SectionHeader(title: month) {
                                Text("\(items.count)")
                                    .font(.system(size: 12, weight: .medium).monospacedDigit())
                                    .foregroundStyle(Ink.secondary)
                            }
                            Card(padding: 0) {
                                VStack(spacing: 0) {
                                    ForEach(Array(items.enumerated()), id: \.element.id) { index, milestone in
                                        if index > 0 { Hairline(inset: 18) }
                                        MilestoneRow(milestone: milestone, showsDate: true)
                                            .padding(.horizontal, 18)
                                            .padding(.vertical, 13)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, Metric.gutter)
                .padding(.top, 10)
                .padding(.bottom, 120)
            }
            .scrollIndicators(.hidden)
        }
        .navigationTitle("Milestones")
        .navigationBarTitleDisplayMode(.inline)
    }
}

struct MilestoneRow: View {
    let milestone: Milestone
    var showsDate = false
    @Environment(AppSettings.self) private var settings

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: milestone.kind.symbol)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(Ink.primary)
                .frame(width: 28, height: 28)
                .background(Ink.surfaceHigh, in: .circle)

            VStack(alignment: .leading, spacing: 2) {
                Text(MilestoneFormatter.headline(for: milestone, unit: settings.unit))
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Ink.primary)
                    .lineLimit(1)
                Text(caption)
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }
            Spacer(minLength: 0)
            if showsDate {
                Text(milestone.achievedAt.formatted(.dateTime.day().month(.abbreviated)))
                    .font(.system(size: 11, weight: .medium).monospacedDigit())
                    .foregroundStyle(Ink.tertiary)
            }
        }
        .contentShape(.rect)
    }

    private var caption: String {
        var parts = [milestone.kind.label]
        if milestone.previousValue > 0 {
            let delta = milestone.value - milestone.previousValue
            switch milestone.kind {
            case .heaviestSet, .estimatedMax, .volumeRecord, .lifetimeVolume:
                parts.append("+\(Format.weight(delta, in: settings.unit)) \(settings.unit.short)")
            default:
                parts.append("+\(Format.number(delta, maxFractionDigits: 0))")
            }
        }
        if showsDate == false {
            parts.append(Format.relativeDay(milestone.achievedAt))
        }
        return parts.joined(separator: " · ")
    }
}
