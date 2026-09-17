import SwiftUI

/// The step indicator that runs along the top of every screen.
struct StageRail: View {
    let stages: [String]
    let current: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(Array(stages.enumerated()), id: \.offset) { index, title in
                HStack(spacing: 6) {
                    Text(String(format: "%02d", index + 1))
                        .font(.railLabel)
                        .foregroundStyle(index == current ? Theme.primary : Theme.tertiary)
                    Text(title)
                        .railLabelStyle(index == current ? Theme.secondary : Theme.tertiary)
                }
                .padding(.trailing, 14)
                .opacity(index <= current ? 1 : 0.45)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.18), value: current)
    }
}

/// A hairline rule.
struct Hairline: View {
    var colour: Color = Theme.hairline
    var body: some View {
        Rectangle().fill(colour).frame(height: 0.5)
    }
}

/// Small monospaced key/value row, used for every readout in the app.
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
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(Capsule().fill(colour.opacity(0.10)))
        .hairlineBorder(Capsule(), colour: colour.opacity(0.25))
    }
}

/// The single slider in the app. Hairline track, monospaced readout, no thumb
/// shadow, and a detent at each tenth so it feels notched rather than loose.
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
        VStack(alignment: .leading, spacing: 10) {
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
                    Capsule().fill(Theme.hairline).frame(height: 2)
                    Capsule().fill(accent)
                        .frame(width: max(0, width * fraction), height: 2)
                    Circle()
                        .fill(Theme.primary)
                        .frame(width: isDragging ? 18 : 14, height: isDragging ? 18 : 14)
                        .overlay(Circle().strokeBorder(Theme.background, lineWidth: 2))
                        .offset(x: max(0, width * fraction) - (isDragging ? 9 : 7))
                }
                .frame(height: 28)
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
            .frame(height: 28)
        }
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }
}

/// Segmented picker drawn from small vector glyphs rather than text.
struct ShapePicker: View {
    @Binding var selection: CellShape
    @Environment(\.signalAccent) private var accent

    var body: some View {
        HStack(spacing: 8) {
            ForEach(CellShape.allCases) { shape in
                Button {
                    selection = shape
                } label: {
                    VStack(spacing: 7) {
                        ShapeGlyph(shape: shape)
                            .fill(selection == shape ? accent : Theme.secondary)
                            .frame(width: 16, height: 16)
                        Text(shape.label).railLabelStyle(selection == shape ? Theme.primary : Theme.tertiary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(selection == shape ? Color.white.opacity(0.05) : .clear)
                    )
                    .hairlineBorder(RoundedRectangle(cornerRadius: 12, style: .continuous),
                                    colour: selection == shape ? Theme.hairlineStrong : Theme.hairline)
                }
                .buttonStyle(.plain)
            }
        }
        .animation(.easeOut(duration: 0.14), value: selection)
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

/// The bottom chrome. Controls live here; content never does.
struct BottomBar<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            content
                .padding(.horizontal, Theme.gutter)
                .padding(.top, 16)
                .padding(.bottom, 8)
        }
        .background(.clear)
        .liquidGlass(UnevenRoundedRectangle(topLeadingRadius: 24, bottomLeadingRadius: 0,
                                            bottomTrailingRadius: 0, topTrailingRadius: 24,
                                            style: .continuous))
    }
}
