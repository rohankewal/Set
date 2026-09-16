import SwiftUI

// MARK: - Surfaces

struct Card<Content: View>: View {
    var padding: CGFloat = 18
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Ink.surface, in: .rect(cornerRadius: Metric.cardRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: Metric.cardRadius, style: .continuous)
                    .strokeBorder(Ink.line, lineWidth: Metric.hairline)
            }
    }
}

struct Hairline: View {
    var inset: CGFloat = 0

    var body: some View {
        Rectangle()
            .fill(Ink.line)
            .frame(height: Metric.hairline)
            .padding(.leading, inset)
    }
}

struct SectionHeader<Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: Trailing

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).microLabelStyle()
            Spacer(minLength: 8)
            trailing
        }
    }
}

extension SectionHeader where Trailing == EmptyView {
    init(_ title: String) {
        self.init(title: title) { EmptyView() }
    }
}

// MARK: - Readouts

/// Large monospaced number with an optional unit, optically aligned.
struct Readout: View {
    let value: String
    var unit: String?
    var size: CGFloat = 34
    var weight: Font.Weight = .medium
    var color: Color = Ink.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.readout(size, weight: weight))
                .readoutTracking(size)
                .foregroundStyle(color)
                .contentTransition(.numericText())
            if let unit {
                Text(unit)
                    .font(.system(size: max(11, size * 0.34), weight: .medium))
                    .foregroundStyle(Ink.tertiary)
            }
        }
    }
}

struct StatTile: View {
    let label: String
    let value: String
    var unit: String?
    var caption: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label).microLabelStyle()
            Readout(value: value, unit: unit, size: 26)
            if let caption {
                Text(caption)
                    .font(.system(size: 12))
                    .foregroundStyle(Ink.tertiary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Buttons

/// The one high-contrast control in the app: inverted fill, tight radius.
struct InkButtonStyle: ButtonStyle {
    var prominent = true
    var height: CGFloat = 54

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 16, weight: .semibold))
            .foregroundStyle(prominent ? Ink.onAccent : Ink.primary)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background {
                if prominent {
                    RoundedRectangle(cornerRadius: Metric.controlRadius + 2, style: .continuous)
                        .fill(Ink.accent)
                } else {
                    RoundedRectangle(cornerRadius: Metric.controlRadius + 2, style: .continuous)
                        .fill(Ink.surfaceHigh)
                }
            }
            .opacity(configuration.isPressed ? 0.82 : 1)
            .scaleEffect(configuration.isPressed ? 0.985 : 1)
            .animation(Motion.tick, value: configuration.isPressed)
    }
}

/// Compact bordered control for secondary actions and chips.
struct QuietButtonStyle: ButtonStyle {
    var horizontal: CGFloat = 14
    var vertical: CGFloat = 9

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(Ink.primary)
            .padding(.horizontal, horizontal)
            .padding(.vertical, vertical)
            .background(Ink.surface, in: .capsule)
            .overlay { Capsule().strokeBorder(Ink.line, lineWidth: Metric.hairline) }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .scaleEffect(configuration.isPressed ? 0.97 : 1)
            .animation(Motion.tick, value: configuration.isPressed)
    }
}

/// Circular icon button, used in toolbars and set rows.
struct IconButtonStyle: ButtonStyle {
    var size: CGFloat = 34
    var filled = false

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: size * 0.42, weight: .semibold))
            .foregroundStyle(filled ? Ink.onAccent : Ink.primary)
            .frame(width: size, height: size)
            .background {
                Circle().fill(filled ? Ink.accent : Ink.surfaceHigh)
            }
            .opacity(configuration.isPressed ? 0.72 : 1)
            .scaleEffect(configuration.isPressed ? 0.92 : 1)
            .animation(Motion.tick, value: configuration.isPressed)
    }
}

// MARK: - Set completion control

struct CheckBadge: View {
    let isOn: Bool
    var size: CGFloat = 30

    var body: some View {
        ZStack {
            Circle()
                .fill(isOn ? Ink.accent : Color.clear)
            Circle()
                .strokeBorder(isOn ? Color.clear : Ink.line, lineWidth: 1.2)
            Image(systemName: "checkmark")
                .font(.system(size: size * 0.42, weight: .bold))
                .foregroundStyle(Ink.onAccent)
                .opacity(isOn ? 1 : 0)
                .scaleEffect(isOn ? 1 : 0.6)
        }
        .frame(width: size, height: size)
        .animation(Motion.snap, value: isOn)
    }
}

// MARK: - Bars

/// Hairline-thin progress bar. Used for rest, weekly volume, goal progress.
struct ThinBar: View {
    let progress: Double
    var height: CGFloat = 4
    var track: Color = Ink.line
    var fill: Color = Ink.primary

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(track)
                Capsule()
                    .fill(fill)
                    .frame(width: max(0, min(1, progress)) * proxy.size.width)
            }
        }
        .frame(height: height)
    }
}

// MARK: - Empty states

struct EmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(Ink.tertiary)
                .padding(.bottom, 2)
            Text(title)
                .font(.system(size: 17, weight: .medium))
                .foregroundStyle(Ink.primary)
            Text(message)
                .font(.system(size: 14))
                .foregroundStyle(Ink.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 44)
    }
}

// MARK: - Chips

struct Chip: View {
    let text: String
    var isSelected = false

    var body: some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isSelected ? Ink.onAccent : Ink.secondary)
            .padding(.horizontal, 13)
            .padding(.vertical, 7)
            .background {
                Capsule().fill(isSelected ? Ink.accent : Ink.surface)
            }
            .overlay {
                Capsule().strokeBorder(isSelected ? Color.clear : Ink.line, lineWidth: Metric.hairline)
            }
    }
}

// MARK: - Screen scaffold

/// Every screen sits on the same canvas with the same gutter, which is most of
/// what makes the app feel like one object.
struct Screen<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Ink.canvas.ignoresSafeArea()
            content
        }
        .tint(Ink.primary)
    }
}

// MARK: - Rest ring

/// Minimal countdown ring: a single stroke that drains clockwise.
struct RestRing: View {
    let progress: Double
    var size: CGFloat = 26
    var lineWidth: CGFloat? = nil

    var body: some View {
        let stroke = lineWidth ?? max(2, size * 0.09)
        ZStack {
            Circle()
                .strokeBorder(Ink.line, lineWidth: stroke)
            Circle()
                .trim(from: 0, to: max(0.001, 1 - min(1, max(0, progress))))
                .stroke(Ink.primary, style: StrokeStyle(lineWidth: stroke, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .padding(stroke / 2)
        }
        .frame(width: size, height: size)
        .animation(.linear(duration: 0.5), value: progress)
    }
}

// MARK: - Week strip

/// Seven marks, one per day, filled when something was logged.
struct WeekStrip: View {
    /// Monday-first flags for the current week.
    let trained: [Bool]
    var todayIndex: Int

    private let symbols = ["M", "T", "W", "T", "F", "S", "S"]

    var body: some View {
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { index in
                VStack(spacing: 8) {
                    Text(symbols[index])
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(index == todayIndex ? Ink.primary : Ink.tertiary)
                    ZStack {
                        Circle()
                            .strokeBorder(Ink.line, lineWidth: 1)
                            .frame(width: 22, height: 22)
                        if trained.indices.contains(index), trained[index] {
                            Circle().fill(Ink.accent).frame(width: 22, height: 22)
                            Image(systemName: "checkmark")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(Ink.onAccent)
                        } else if index == todayIndex {
                            Circle().fill(Ink.line).frame(width: 5, height: 5)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}
