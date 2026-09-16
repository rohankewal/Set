import ActivityKit
import SwiftUI
import WidgetKit

/// The rest timer on the Lock Screen and in the Dynamic Island.
///
/// Same monochrome rules as the app: one ink, one surface, no colour. The timer
/// is rendered by the system from an end date, so it stays exact without the app
/// running.
struct RestLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RestActivityAttributes.self) { context in
            lockScreen(context)
                .activityBackgroundTint(Color.black.opacity(0.55))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.state.isPaused ? "PAUSED" : "REST")
                            .font(.system(size: 10, weight: .bold))
                            .tracking(1.6)
                            .foregroundStyle(.secondary)
                        Text(context.attributes.sessionTitle)
                            .font(.system(size: 13, weight: .medium))
                            .lineLimit(1)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    countdown(context, size: 30, weight: .semibold)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack(spacing: 8) {
                        Text(context.state.nextUp)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                        Text("^[\(context.state.setsLogged) set](inflect: true)")
                            .font(.system(size: 12, weight: .medium).monospacedDigit())
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.top, 2)
                }
            } compactLeading: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 12, weight: .semibold))
            } compactTrailing: {
                countdown(context, size: 13, weight: .semibold)
                    .frame(minWidth: 38)
            } minimal: {
                Image(systemName: context.state.isPaused ? "pause.fill" : "timer")
                    .font(.system(size: 12, weight: .semibold))
            }
            .keylineTint(.white)
        }
    }

    // MARK: Lock Screen

    private func lockScreen(_ context: ActivityViewContext<RestActivityAttributes>) -> some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(context.state.isPaused ? "REST PAUSED" : "REST")
                    .font(.system(size: 10, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(.secondary)

                countdown(context, size: 42, weight: .medium)

                Text(context.state.nextUp.isEmpty ? context.attributes.sessionTitle : context.state.nextUp)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            VStack(alignment: .trailing, spacing: 4) {
                Text("\(context.state.setsLogged)")
                    .font(.system(size: 26, weight: .medium).monospacedDigit())
                Text("SETS")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.4)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
    }

    /// A live countdown when running, a frozen number when paused.
    @ViewBuilder
    private func countdown(
        _ context: ActivityViewContext<RestActivityAttributes>,
        size: CGFloat,
        weight: Font.Weight
    ) -> some View {
        if let endsAt = context.state.endsAt, !context.state.isPaused {
            Text(timerInterval: Date.now...endsAt, countsDown: true)
                .font(.system(size: size, weight: weight).monospacedDigit())
                .monospacedDigit()
        } else {
            Text(clock(context.state.remaining))
                .font(.system(size: size, weight: weight).monospacedDigit())
        }
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
