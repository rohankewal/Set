import SwiftUI

/// The bottom control of a workout. Idle it's a slim bar with a play button;
/// start a rest and it grows into a dial — one big tap target for pause/resume,
/// a ring that drains, and ±15s either side. One control, three states, so
/// there's never a question of what to press between sets.
struct RestDock: View {
    @Environment(AppSettings.self) private var settings
    @Environment(WorkoutEngine.self) private var engine

    /// Exercise the next rest belongs to, used for the alert copy.
    var exercise: String = ""

    @Namespace private var dial
    @State private var breathing = false

    var body: some View {
        VStack(spacing: 0) {
            if engine.isRestActive {
                expanded
                    .transition(.asymmetric(
                        insertion: .scale(scale: 0.86, anchor: .bottom).combined(with: .opacity),
                        removal: .scale(scale: 0.9, anchor: .bottom).combined(with: .opacity)
                    ))
            } else {
                compact
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
        .animation(Motion.snap, value: engine.isRestActive)
        .animation(Motion.snap, value: engine.isRestPaused)
    }

    // MARK: Expanded dial

    private var expanded: some View {
        VStack(spacing: 18) {
            ZStack {
                // Track + draining progress.
                Circle()
                    .strokeBorder(Ink.line, lineWidth: 5)
                Circle()
                    .trim(from: 0, to: max(0.0001, 1 - engine.restProgress))
                    .stroke(Ink.primary, style: StrokeStyle(lineWidth: 5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(2.5)
                    .animation(.linear(duration: 0.3), value: engine.restProgress)

                // Breathing fill, alive only while the clock runs.
                Circle()
                    .fill(Ink.surface)
                    .padding(16)
                    .scaleEffect(breathing && engine.isResting ? 1 : 0.965)
                    .opacity(engine.isResting ? 1 : 0.75)

                VStack(spacing: 8) {
                    TimelineView(.periodic(from: .now, by: 0.2)) { _ in
                        Text(Format.clock(engine.restRemaining))
                            .font(.readout(54, weight: .medium))
                            .readoutTracking(54)
                            .foregroundStyle(Ink.primary)
                            .contentTransition(.numericText(countsDown: true))
                    }
                    Image(systemName: engine.isResting ? "pause.fill" : "play.fill")
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(Ink.tertiary)
                        .contentTransition(.symbolEffect(.replace))
                    Text(engine.isRestPaused ? "Paused" : "Rest")
                        .microLabelStyle(Ink.tertiary)
                }
            }
            .frame(width: 210, height: 210)
            .contentShape(.circle)
            .onTapGesture { engine.toggleRest(exercise: exercise) }
            .accessibilityAddTraits(.isButton)
            .accessibilityLabel(engine.isResting ? "Pause rest" : "Resume rest")
            .accessibilityValue(Format.clock(engine.restRemaining))

            HStack(spacing: 10) {
                Button("−15") { engine.adjustRest(by: -15) }
                    .buttonStyle(QuietButtonStyle(horizontal: 16, vertical: 10))
                Button("Skip") { engine.endRest() }
                    .buttonStyle(QuietButtonStyle(horizontal: 22, vertical: 10))
                Button("+15") { engine.adjustRest(by: 15) }
                    .buttonStyle(QuietButtonStyle(horizontal: 16, vertical: 10))
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .glassEffect(.regular, in: .rect(cornerRadius: 30, style: .continuous))
        .task(id: engine.isResting) {
            // Restart the breath on every resume so it stays in phase.
            breathing = false
            guard engine.isResting else { return }
            withAnimation(.easeInOut(duration: 1.7).repeatForever(autoreverses: true)) {
                breathing = true
            }
        }
    }

    // MARK: Compact bar

    private var compact: some View {
        HStack(spacing: 14) {
            Button {
                engine.startRest(seconds: settings.defaultRestSeconds, exercise: exercise)
            } label: {
                Image(systemName: "play.fill")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(Ink.onAccent)
                    .frame(width: 48, height: 48)
                    .background(Ink.accent, in: .circle)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Start rest timer")

            VStack(alignment: .leading, spacing: 2) {
                Text("Rest timer").microLabelStyle()
                Text(Format.clock(Double(settings.defaultRestSeconds)))
                    .font(.readout(20, weight: .semibold))
                    .foregroundStyle(Ink.primary)
                    .contentTransition(.numericText())
            }

            Spacer(minLength: 0)

            HStack(spacing: 8) {
                Button {
                    settings.defaultRestSeconds -= 15
                    Haptics.play(.tick)
                } label: {
                    Image(systemName: "minus")
                }
                .buttonStyle(IconButtonStyle(size: 34))
                Button {
                    settings.defaultRestSeconds += 15
                    Haptics.play(.tick)
                } label: {
                    Image(systemName: "plus")
                }
                .buttonStyle(IconButtonStyle(size: 34))
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .glassEffect(.regular, in: .rect(cornerRadius: 26, style: .continuous))
    }
}
