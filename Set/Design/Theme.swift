import SwiftUI

// MARK: - Palette
//
// The entire app is monochrome on purpose: one ink, one surface, five greys.
// Colours are resolved dynamically so light and dark are true inversions of
// each other rather than two separately tuned themes.

#if canImport(UIKit)
import UIKit

private func dynamic(light: Double, dark: Double) -> Color {
    Color(UIColor { trait in
        UIColor(white: trait.userInterfaceStyle == .dark ? dark : light, alpha: 1)
    })
}
#else
private func dynamic(light: Double, dark: Double) -> Color {
    Color(white: light)
}
#endif

enum Ink {
    /// Page background. Near-black in dark, paper-white in light.
    static let canvas = dynamic(light: 1.00, dark: 0.04)
    /// Raised surfaces: cards, rows, sheets.
    static let surface = dynamic(light: 0.96, dark: 0.09)
    /// Surfaces one step above `surface`.
    static let surfaceHigh = dynamic(light: 0.92, dark: 0.14)
    /// Primary type.
    static let primary = dynamic(light: 0.05, dark: 0.98)
    /// Secondary type, still readable at small sizes.
    static let secondary = dynamic(light: 0.42, dark: 0.64)
    /// Labels, captions, disabled states.
    static let tertiary = dynamic(light: 0.60, dark: 0.44)
    /// Hairlines.
    static let line = dynamic(light: 0.87, dark: 0.20)
    /// Inverted fill — the one high-contrast accent the app allows itself.
    static let accent = dynamic(light: 0.05, dark: 0.98)
    static let onAccent = dynamic(light: 1.00, dark: 0.04)
}

// MARK: - Metrics

enum Metric {
    static let gutter: CGFloat = 20
    static let cardRadius: CGFloat = 22
    static let controlRadius: CGFloat = 14
    static let rowHeight: CGFloat = 46
    static let hairline: CGFloat = 0.5
}

// MARK: - Type

extension Font {
    /// Oversized readouts: timers, weights, totals.
    static func readout(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .default).monospacedDigit()
    }
    static let microLabel = Font.system(size: 11, weight: .semibold)
    static let rowTitle = Font.system(size: 17, weight: .medium)
    static let rowValue = Font.system(size: 16, weight: .regular).monospacedDigit()
}

extension View {
    /// Tiny wide-tracked uppercase caption used for every section header.
    func microLabelStyle(_ color: Color = Ink.tertiary) -> some View {
        self.font(.microLabel)
            .tracking(1.1)
            .textCase(.uppercase)
            .foregroundStyle(color)
    }

    /// Tight optical tracking for large numerals.
    func readoutTracking(_ size: CGFloat) -> some View {
        self.tracking(-size * 0.035)
    }
}

// MARK: - Motion

enum Motion {
    static let snap = Animation.spring(response: 0.28, dampingFraction: 0.86)
    static let gentle = Animation.spring(response: 0.42, dampingFraction: 0.9)
    static let tick = Animation.easeOut(duration: 0.18)
}
