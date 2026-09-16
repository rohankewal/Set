import SwiftUI

/// What to hang on each side of the bar. Most apps show a list of numbers; this
/// draws the plates at proportional size so it reads at a glance from the floor.
struct PlateCalculatorView: View {
    let totalKg: Double

    @Environment(AppSettings.self) private var settings
    @Environment(\.dismiss) private var dismiss

    private var unit: WeightUnit { settings.unit }
    private var barDisplay: Double { unit.fromKilograms(settings.barWeightKg) }
    private var totalDisplay: Double { unit.fromKilograms(totalKg) }

    private var loading: PlateMath.Loading? {
        PlateMath.loading(forTotal: totalDisplay, barWeight: barDisplay, unit: unit)
    }

    var body: some View {
        NavigationStack {
            Screen {
                ScrollView {
                  VStack(spacing: 26) {
                    VStack(spacing: 4) {
                        Text("Target").microLabelStyle()
                        Readout(value: Format.plate(totalDisplay), unit: unit.short, size: 44)
                    }

                    if let loading {
                        barGraphic(loading)

                        VStack(spacing: 10) {
                            ForEach(Array(PlateMath.grouped(loading.perSide).enumerated()), id: \.offset) { _, row in
                                HStack {
                                    Text("\(row.count) ×")
                                        .font(.system(size: 15, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Ink.tertiary)
                                        .frame(width: 40, alignment: .leading)
                                    Text("\(Format.plate(row.plate)) \(unit.short)")
                                        .font(.system(size: 17, weight: .medium).monospacedDigit())
                                        .foregroundStyle(Ink.primary)
                                    Spacer()
                                    Text("per side")
                                        .font(.system(size: 12))
                                        .foregroundStyle(Ink.tertiary)
                                }
                                .padding(.horizontal, 18)
                                .padding(.vertical, 11)
                                .background(Ink.surface, in: .rect(cornerRadius: Metric.controlRadius, style: .continuous))
                            }

                            if loading.isBarOnly {
                                Text("Empty bar")
                                    .font(.system(size: 15, weight: .medium))
                                    .foregroundStyle(Ink.secondary)
                            }

                            if !loading.isExact {
                                Text("Closest loadable weight is \(Format.plate(loading.achievedTotal)) \(unit.short).")
                                    .font(.system(size: 12))
                                    .foregroundStyle(Ink.tertiary)
                                    .multilineTextAlignment(.center)
                            }
                        }
                    } else {
                        EmptyState(
                            symbol: "exclamationmark.circle",
                            title: "Below the bar",
                            message: "The target is lighter than the empty bar (\(Format.plate(barDisplay)) \(unit.short))."
                        )
                    }

                    HStack(spacing: 12) {
                        Text("Bar").microLabelStyle()
                        Spacer()
                        Stepper(
                            value: Binding(
                                get: { settings.barWeightKg },
                                set: { settings.barWeightKg = $0 }
                            ),
                            in: 0...100,
                            step: unit == .kilograms ? 2.5 : 2.26796
                        ) {
                            EmptyView()
                        }
                        .labelsHidden()
                        Text("\(Format.plate(barDisplay)) \(unit.short)")
                            .font(.rowValue)
                            .foregroundStyle(Ink.secondary)
                            .frame(width: 70, alignment: .trailing)
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 12)
                    .background(Ink.surface, in: .rect(cornerRadius: Metric.cardRadius, style: .continuous))
                  }
                  .padding(.horizontal, Metric.gutter)
                  .padding(.top, 6)
                  .padding(.bottom, 24)
                }
                .scrollIndicators(.hidden)
            }
            .navigationTitle("Plates")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }.font(.system(size: 15, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }

    /// Half a barbell, drawn to scale: the sleeve, then each plate sized by its
    /// share of the heaviest plate on the rack.
    private func barGraphic(_ loading: PlateMath.Loading) -> some View {
        let heaviest = PlateMath.plates(for: unit).first ?? 25
        return HStack(alignment: .center, spacing: 3) {
            Rectangle()
                .fill(Ink.tertiary)
                .frame(width: 54, height: 7)
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Ink.tertiary)
                .frame(width: 6, height: 26)
            ForEach(Array(loading.perSide.enumerated()), id: \.offset) { _, plate in
                let scale = max(0.34, plate / heaviest)
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(Ink.primary)
                    .frame(width: max(9, 15 * scale), height: 116 * scale)
                    .overlay {
                        RoundedRectangle(cornerRadius: 3, style: .continuous)
                            .strokeBorder(Ink.canvas.opacity(0.6), lineWidth: 0.5)
                    }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 120)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
        .background(Ink.surface, in: .rect(cornerRadius: Metric.cardRadius, style: .continuous))
        .accessibilityLabel("Plates per side")
        .accessibilityValue(
            PlateMath.grouped(loading.perSide)
                .map { "\($0.count) times \(Format.number($0.plate))" }
                .joined(separator: ", ")
        )
    }
}
