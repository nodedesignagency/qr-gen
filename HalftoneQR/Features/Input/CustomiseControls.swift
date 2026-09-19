import SwiftUI

/// The customise controls, in the glass language of screen one.
///
/// They arrive on the page as the card lands and sit under it: the card's
/// state, one slider, and a row of round controls. Measurements follow the
/// upload and URL surfaces — 353 wide, 20pt corners, 21/16 padding — so the
/// page reads as one design rather than a form bolted under a picture.

/// The single slider in the app, on glass: a white track, a white thumb, and a
/// detent at each hundredth so it feels notched rather than loose.
struct GlassSlider: View {
    let title: String
    @Binding var value: Double
    var range: ClosedRange<Double> = 0...1
    var onEditingChanged: ((Bool) -> Void)?

    @State private var isDragging = false

    private var fraction: Double {
        (value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title)
                    .snType(16, weight: .medium)
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Text(String(format: "%.2f", value))
                    .snType(16, weight: .semibold)
                    .foregroundStyle(.white)
                    .monospacedDigit()
            }
            GeometryReader { geometry in
                let width = geometry.size.width
                let thumb: CGFloat = isDragging ? 26 : 22
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.28)).frame(height: 4)
                    Capsule().fill(Color.white)
                        .frame(width: max(0, width * fraction), height: 4)
                    Circle()
                        .fill(Color.white)
                        .frame(width: thumb, height: thumb)
                        .shadow(color: .black.opacity(0.22), radius: 4, y: 2)
                        .offset(x: max(0, width * fraction) - thumb / 2)
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
        .padding(.horizontal, 21)
        .padding(.vertical, 16)
        .glassSurface(cornerRadius: 20)
        .animation(.easeOut(duration: 0.12), value: isDragging)
    }
}

/// One of the round controls under the card: a glass disc with a glyph, and a
/// label beneath. Tapping cycles the option; `isSelected` lights the rim for
/// the one control that is a switch rather than a cycle.
struct GlassControl<Glyph: View>: View {
    let label: String
    var isSelected: Bool = false
    var isEnabled: Bool = true
    let action: () -> Void
    @ViewBuilder var glyph: Glyph

    var body: some View {
        Button(action: action) {
            VStack(spacing: 9) {
                glyph
                    .frame(width: 56, height: 56)
                    .glassSurface(cornerRadius: 28, isHighlighted: isSelected)
                Text(label)
                    .snType(13, weight: .medium)
                    .foregroundStyle(.white.opacity(0.85))
            }
            .frame(maxWidth: .infinity)
            .opacity(isEnabled ? 1 : 0.4)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .animation(.easeOut(duration: 0.15), value: isSelected)
    }
}

/// A small glass chip: a dot and a label. The card's state, under the card.
struct GlassPill: View {
    let text: String
    var dot: Color = .white

    var body: some View {
        HStack(spacing: 7) {
            Circle().fill(dot).frame(width: 5, height: 5)
            Text(text)
                .snType(13, weight: .medium)
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .frame(height: 30)
        .glassSurface(cornerRadius: 15)
    }
}

/// The "Centre" control's mark: a frame with the emblem lit or not.
struct EmblemGlyph: View {
    let isOn: Bool
    var colour: Color = .white

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .strokeBorder(colour, lineWidth: 1.6)
                .frame(width: 21, height: 21)
            Circle()
                .fill(colour.opacity(isOn ? 1 : 0.35))
                .frame(width: 8, height: 8)
        }
    }
}

/// The "Focus" control's mark: the dots and the mark, the mark ahead when on.
struct FocusGlyph: View {
    let isOn: Bool
    var colour: Color = .white

    var body: some View {
        ZStack {
            LatticeGlyph(shape: .dot, colour: colour.opacity(isOn ? 0.35 : 0.9))
            RoundedRectangle(cornerRadius: 3.5, style: .continuous)
                .fill(colour)
                .frame(width: 11, height: 11)
                .rotationEffect(.degrees(45))
        }
    }
}

/// A small mark that hints at the selected choreography.
struct MotionGlyph: View {
    let choreography: Choreography
    var colour: Color = .white

    var body: some View {
        switch choreography {
        case .bigBang:
            ZStack {
                ForEach(0..<6, id: \.self) { index in
                    Capsule().fill(colour.opacity(0.7))
                        .frame(width: 2.2, height: 6)
                        .offset(y: -8)
                        .rotationEffect(.degrees(Double(index) * 60))
                }
                Circle().fill(colour).frame(width: 6, height: 6)
            }
            .frame(width: 22, height: 22)
        case .scanline:
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule().fill(colour.opacity(index == 0 ? 1 : 0.4))
                        .frame(width: 20, height: 2.5)
                }
            }
        case .radial:
            ZStack {
                Circle().strokeBorder(colour.opacity(0.35), lineWidth: 1.5).frame(width: 22, height: 22)
                Circle().fill(colour).frame(width: 8, height: 8)
            }
        case .diagonal:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 20))
                path.addLine(to: CGPoint(x: 20, y: 0))
            }
            .stroke(colour, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 20, height: 20)
        case .spiral:
            Circle()
                .trim(from: 0.06, to: 0.8)
                .stroke(colour, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 20, height: 20)
        case .develop:
            LatticeGlyph(shape: .dot, colour: colour)
        case .structureFirst:
            FinderGlyph(style: .rounded, colour: colour)
        }
    }
}

extension CellShape {
    var next: CellShape {
        let all = CellShape.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

extension FinderStyle {
    var next: FinderStyle {
        let all = FinderStyle.allCases
        return all[(all.firstIndex(of: self)! + 1) % all.count]
    }
}

extension Choreography {
    var next: Choreography {
        let all = Choreography.selectable
        guard let index = all.firstIndex(of: self) else { return all[0] }
        return all[(index + 1) % all.count]
    }
}
