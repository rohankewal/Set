import SwiftUI
import WatchKit

/// The whole watch app: what to lift, and one button to log it.
///
/// Same premise as Focus mode on the phone — a single target you can hit without
/// looking. Nothing here browses history; that's what the phone is for.
struct WatchRootView: View {
    @Environment(WatchSessionLink.self) private var link

    private var snapshot: WatchLink.Snapshot { link.snapshot }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            if snapshot.isResting {
                rest
            } else if snapshot.isRunning {
                logging
            } else {
                idle
            }
        }
        .animation(.snappy(duration: 0.25), value: snapshot.isResting)
        .animation(.snappy(duration: 0.25), value: snapshot.isRunning)
    }

    // MARK: Logging

    private var logging: some View {
        VStack(spacing: 6) {
            Text(snapshot.exercise.uppercased())
                .font(.system(size: 11, weight: .semibold))
                .tracking(0.8)
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                if snapshot.usesWeight {
                    Text(snapshot.weight)
                        .font(.system(size: 34, weight: .medium).monospacedDigit())
                    Text(snapshot.unit)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.white.opacity(0.5))
                    Text("×")
                        .font(.system(size: 20, weight: .light))
                        .foregroundStyle(.white.opacity(0.4))
                }
                Text("\(snapshot.reps)")
                    .font(.system(size: 34, weight: .medium).monospacedDigit())
            }
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            Text("Set \(snapshot.setNumber)")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))

            Button {
                link.send(.logSet)
                WKInterfaceDevice.current().play(.success)
            } label: {
                Label("Log set", systemImage: "checkmark")
                    .font(.system(size: 15, weight: .semibold))
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
            .padding(.top, 2)

            HStack(spacing: 6) {
                Button {
                    link.send(.previousExercise)
                } label: {
                    Image(systemName: "chevron.left")
                }
                Button {
                    link.send(.nextExercise)
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .font(.system(size: 12, weight: .semibold))
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.15))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
    }

    // MARK: Rest

    private var rest: some View {
        VStack(spacing: 8) {
            Text(snapshot.isRestPaused ? "PAUSED" : "REST")
                .font(.system(size: 10, weight: .bold))
                .tracking(2)
                .foregroundStyle(.white.opacity(0.5))

            Group {
                if let endsAt = snapshot.restEndsAt, !snapshot.isRestPaused {
                    Text(timerInterval: Date.now...endsAt, countsDown: true)
                        .font(.system(size: 40, weight: .medium).monospacedDigit())
                } else {
                    Text(clock(snapshot.restRemaining))
                        .font(.system(size: 40, weight: .medium).monospacedDigit())
                }
            }
            .foregroundStyle(.white)
            .minimumScaleFactor(0.6)
            .lineLimit(1)

            HStack(spacing: 6) {
                Button("+15") { link.send(.addFifteen) }
                Button(snapshot.isRestPaused ? "Resume" : "Pause") { link.send(.toggleRest) }
                Button("Skip") { link.send(.skipRest) }
            }
            .font(.system(size: 12, weight: .medium))
            .buttonStyle(.bordered)
            .tint(.white.opacity(0.15))
            .foregroundStyle(.white)
        }
        .padding(.horizontal, 6)
    }

    // MARK: Idle

    private var idle: some View {
        VStack(spacing: 10) {
            Image(systemName: link.isReachable ? "iphone" : "iphone.slash")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(.white.opacity(0.5))
            Text(link.isReachable ? "No workout running" : "Open Set on your iPhone")
                .font(.system(size: 13))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 10)
    }

    private func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
