import SwiftUI

/// The screen title and the step dots. Deliberately quiet: a name, a position,
/// and a way out. Nothing competes with the card.
struct StageHeader: View {
    let title: String
    let step: Int
    let stepCount: Int
    var trailingLabel: String?
    var showsTrailing: Bool = false
    var onTrailing: () -> Void = {}

    var body: some View {
        HStack(alignment: .center) {
            VStack(alignment: .leading, spacing: 7) {
                Text(title)
                    .font(.screenTitle)
                    .foregroundStyle(Theme.primary)
                StepDots(step: step, count: stepCount)
            }
            Spacer(minLength: 12)
            if showsTrailing, let trailingLabel {
                Button(action: onTrailing) {
                    Text(trailingLabel).railLabelStyle(Theme.secondary)
                        .padding(.horizontal, 13)
                        .frame(height: 32)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .hairlineBorder(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// Progress as four short bars rather than a row of cramped labels.
struct StepDots: View {
    let step: Int
    let count: Int
    @Environment(\.signalAccent) private var accent

    var body: some View {
        HStack(spacing: 5) {
            ForEach(0..<count, id: \.self) { index in
                Capsule()
                    .fill(index == step ? accent : (index < step ? Theme.secondary : Theme.hairlineStrong))
                    .frame(width: index == step ? 20 : 10, height: 3)
            }
        }
        .animation(.easeOut(duration: 0.22), value: step)
    }
}

/// A hairline rule.
struct Hairline: View {
    var colour: Color = Theme.hairline
    var body: some View {
        Rectangle().fill(colour).frame(height: 0.5)
    }
}

/// Small monospaced key/value row.
struct ValueRow: View {
    let key: String
    let value: String
    var tint: Color = Theme.primary

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(key).railLabelStyle()
            Spacer(minLength: 8)
            Text(value)
                .font(.valueLabel)
                .foregroundStyle(tint)
                .multilineTextAlignment(.trailing)
                .lineLimit(2)
                .truncationMode(.middle)
        }
    }
}

/// A status chip: a dot and a short monospaced label.
struct StatusPill: View {
    enum Tone { case neutral, working, good, warn, bad }

    let text: String
    var tone: Tone = .neutral

    private var colour: Color {
        switch tone {
        case .neutral: return Theme.secondary
        case .working: return Theme.defaultAccent
        case .good: return Theme.positive
        case .warn: return Theme.caution
        case .bad: return Theme.negative
        }
    }

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(colour).frame(width: 5, height: 5)
            Text(text)
                .font(.railLabel)
                .tracking(1.0)
                .textCase(.uppercase)
                .foregroundStyle(colour)
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .background(Capsule().fill(colour.opacity(0.10)))
        .hairlineBorder(Capsule(), colour: colour.opacity(0.22))
    }
}

/// One of the circular controls that sit above the action button.
///
/// The glyph carries the meaning and the label underneath names it, which is the
/// pattern the references use — a row of round controls, not a segmented bar.
struct CircleControl<Glyph: View>: View {
    let label: String
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @ViewBuilder var glyph: Glyph

    @Environment(\.signalAccent) private var accent

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.10) : Color.white.opacity(0.035))
                    Circle()
                        .strokeBorder(isSelected ? accent : Theme.hairlineStrong,
                                      lineWidth: isSelected ? 1.4 : 0.5)
                    glyph
                }
                .frame(width: Theme.circleControl, height: Theme.circleControl)
                Text(label)
                    .font(.controlLabel)
                    .foregroundStyle(isSelected ? Theme.primary : Theme.tertiary)
            }
            .frame(maxWidth: .infinity)
            .opacity(isEnabled ? 1 : 0.35)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// The single slider in the app. Hairline track, monospaced readout, and a
/// detent at each hundredth so it feels notched rather than loose.
struct TechSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: ((Bool) -> Void)?

    @Environment(\.signalAccent) private var accent
    @State private var isDragging = false

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack {
                Text(title).railLabelStyle()
                Spacer()
                Text(String(format: "%.2f", value))
                    .font(.valueLabel)
                    .foregroundStyle(isDragging ? accent : Theme.secondary)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                ZStack(alignment: .leading) {
                    Capsule().fill(Theme.hairlineStrong).frame(height: 2)
                    Capsule().fill(accent)
                        .frame(width: max(0, width * fraction), height: 2)
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: isDragging ? 20 : 15, height: isDragging ? 20 : 15)
                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                        .offset(x: max(0, width * fraction) - (isDragging ? 10 : 7.5))
                }
                .frame(height: 30)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { gesture in
                            if !isDragging {
                                isDragging = true
                                onEditingChanged?(true)
                            }
                            let raw = min(max(gesture.location.x / max(width, 1), 0), 1)
                            let span = range.upperBound - range.lowerBound
                            value = range.lowerBound + (raw * span * 100).rounded() / 100
                        }
                        .onEnded { _ in
                            isDragging = false
                            onEditingChanged?(false)
                        }
                )
            }
            .frame(height: 30)
        }
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }
}

/// The three module shapes, drawn as a `Shape` so the picker and the renderer
/// cannot disagree about what a "diamond" is.
struct ShapeGlyph: Shape {
    let shape: CellShape

    func path(in rect: CGRect) -> Path {
        var path = Path()
        switch shape {
        case .square:
            path.addRect(rect)
        case .dot:
            path.addEllipse(in: rect)
        case .diamond:
            path.move(to: CGPoint(x: rect.midX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
            path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
            path.closeSubpath()
        }
        return path
    }
}

/// A 3x3 lattice of the given module shape, used as the "Pixels" glyph.
struct LatticeGlyph: View {
    let shape: CellShape
    var colour: Color = Theme.primary

    var body: some View {
        VStack(spacing: 3) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 3) {
                    ForEach(0..<3, id: \.self) { _ in
                        ShapeGlyph(shape: shape).fill(colour).frame(width: 4.5, height: 4.5)
                    }
                }
            }
        }
    }
}

/// A finder pattern drawn at glyph scale, used as the "Eyes" control.
///
/// Strokes an `AnyShape` rather than carrying a type-erased *insettable* shape:
/// `strokeBorder` would need one, `stroke` does not, and at 20pt the half-pixel
/// difference between them is invisible.
struct FinderGlyph: View {
    let style: FinderStyle
    var colour: Color = Theme.primary

    var body: some View {
        ZStack {
            outline
                .stroke(colour, lineWidth: 2.6)
                .frame(width: 18, height: 18)
            outline
                .fill(colour)
                .frame(width: 7, height: 7)
        }
    }

    private var outline: AnyShape {
        switch style {
        case .square:
            return AnyShape(Rectangle())
        case .rounded:
            return AnyShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        case .circle:
            return AnyShape(Circle())
        }
    }
}

/// The bottom chrome. Controls live here; content never does.
///
/// The opaque floor behind the glass matters: a glass layer with nothing solid
/// beneath it samples whatever sits behind the window, which is how the action
/// button ended up tinted by the desktop.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            content
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 18)
                .padding(.bottom, 6)
        }
        .liquidGlass(Rectangle())
        .background(Theme.background)
    }
}
