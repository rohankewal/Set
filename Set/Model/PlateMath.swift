import Foundation

/// Barbell loading maths. Everything here is unit-aware because plates are
/// physical objects: a 20 kg bar and a 45 lb bar are different bars, and
/// rounding a squat to 102.3 kg helps nobody.
enum PlateMath {
    /// Plate denominations commonly found on a rack, heaviest first.
    static func plates(for unit: WeightUnit) -> [Double] {
        switch unit {
        case .kilograms: [25, 20, 15, 10, 5, 2.5, 1.25]
        case .pounds: [45, 35, 25, 10, 5, 2.5]
        }
    }

    static func defaultBar(for unit: WeightUnit) -> Double {
        switch unit {
        case .kilograms: 20
        case .pounds: 45
        }
    }

    struct Loading: Equatable {
        /// Plate values for one side, heaviest first.
        var perSide: [Double]
        /// What the bar actually weighs once loaded — may be under the target
        /// when the smallest plate can't close the gap.
        var achievedTotal: Double
        var isExact: Bool
        var barWeight: Double

        var isBarOnly: Bool { perSide.isEmpty }
    }

    /// Greedy plate breakdown for one side of the bar.
    static func loading(
        forTotal total: Double,
        barWeight: Double,
        unit: WeightUnit
    ) -> Loading? {
        guard total >= barWeight else { return nil }
        var remainingPerSide = (total - barWeight) / 2
        var chosen: [Double] = []

        for plate in plates(for: unit) {
            while remainingPerSide + 0.0001 >= plate {
                chosen.append(plate)
                remainingPerSide -= plate
            }
        }

        let achieved = barWeight + chosen.reduce(0, +) * 2
        return Loading(
            perSide: chosen,
            achievedTotal: achieved,
            isExact: abs(achieved - total) < 0.01,
            barWeight: barWeight
        )
    }

    /// Groups repeated plates for display: [25, 25, 10] → [(25, 2), (10, 1)].
    static func grouped(_ plates: [Double]) -> [(plate: Double, count: Int)] {
        var result: [(Double, Int)] = []
        for plate in plates {
            if let last = result.last, last.0 == plate {
                result[result.count - 1].1 += 1
            } else {
                result.append((plate, 1))
            }
        }
        return result.map { (plate: $0.0, count: $0.1) }
    }

    /// Rounds a computed load (a warm-up percentage, a progression step) to
    /// something you can actually build on a bar.
    static func round(_ kilograms: Double, to unit: WeightUnit, minimum: Double = 0) -> Double {
        let increment = unit.toKilograms(unit.step)
        guard increment > 0 else { return kilograms }
        let rounded = (kilograms / increment).rounded() * increment
        return max(rounded, minimum)
    }
}
