import Foundation

/// Everything is persisted in kilograms; the unit is purely a presentation choice.
enum WeightUnit: String, Codable, CaseIterable, Sendable {
    case kilograms, pounds

    var short: String {
        switch self {
        case .kilograms: "kg"
        case .pounds: "lb"
        }
    }

    var label: String {
        switch self {
        case .kilograms: "Kilograms"
        case .pounds: "Pounds"
        }
    }

    /// Smallest sensible plate jump in this unit.
    var step: Double {
        switch self {
        case .kilograms: 2.5
        case .pounds: 5
        }
    }

    func fromKilograms(_ kg: Double) -> Double {
        switch self {
        case .kilograms: kg
        case .pounds: kg * 2.2046226218
        }
    }

    func toKilograms(_ value: Double) -> Double {
        switch self {
        case .kilograms: value
        case .pounds: value / 2.2046226218
        }
    }
}

enum Format {
    /// Trims trailing zeros: 72.5 → "72.5", 70.0 → "70".
    static func weight(_ kg: Double, in unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kg)
        return number(value)
    }

    static func number(_ value: Double, maxFractionDigits: Int = 1) -> String {
        let rounded = (value * 10).rounded() / 10
        if abs(rounded.rounded() - rounded) < 0.0001 {
            return String(Int(rounded.rounded()))
        }
        return String(format: "%.\(maxFractionDigits)f", rounded)
    }

    /// Plate denominations need two decimals (1.25 kg) where weights need one.
    static func plate(_ value: Double) -> String {
        if abs(value.rounded() - value) < 0.001 { return String(Int(value.rounded())) }
        let twoDecimals = (value * 100).rounded() / 100
        var text = String(format: "%.2f", twoDecimals)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// Compact tonnage: 12 400 kg → "12.4k".
    static func volume(_ kg: Double, in unit: WeightUnit) -> String {
        let value = unit.fromKilograms(kg)
        if value >= 10_000 { return "\(number(value / 1000))k" }
        return number(value, maxFractionDigits: 0)
    }

    static func clock(_ interval: TimeInterval) -> String {
        let total = max(0, Int(interval.rounded()))
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }

    static func shortDuration(_ interval: TimeInterval) -> String {
        let minutes = Int(interval / 60)
        if minutes >= 60 {
            let h = minutes / 60, m = minutes % 60
            return m == 0 ? "\(h)h" : "\(h)h \(m)m"
        }
        return "\(max(minutes, 1))m"
    }

    static func relativeDay(_ date: Date, calendar: Calendar = .current) -> String {
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: .now)).day ?? 0
        if days < 7 { return date.formatted(.dateTime.weekday(.wide)) }
        return date.formatted(.dateTime.day().month(.abbreviated))
    }
}
