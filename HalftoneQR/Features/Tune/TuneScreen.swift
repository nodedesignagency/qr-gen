import SwiftUI

/// Step two: the symbol is the whole screen, and the controls sit quietly below.
struct TuneScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            QRCard(plan: model.plan,
                   animationKey: model.resolveToken,
                   choreography: model.choreography)
                .padding(.horizontal, Theme.gutter)
                .frame(maxHeight: .infinity)

            HStack(spacing: 12) {
                if model.isRendering {
                    StatusPill(text: "Rendering", tone: .working)
                } else if let plan = model.plan {
                    StatusPill(text: "v\(plan.version) · \(plan.moduleCount)×\(plan.moduleCount)",
                               tone: .neutral)
                }
                Spacer()
                if let analysis = model.analysis, !analysis.isUsable {
                    StatusPill(text: "Weak silhouette", tone: .warn)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
    }
}

/// The tune controls: one slider, then a row of round controls that cycle
/// through their options on tap — the pattern from the reference screens.
struct TuneControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 22) {
            TechSlider(title: "Logo strength", value: $model.config.logoStrength) { editing in
                model.schedulePreview(debounce: editing ? .milliseconds(40) : .zero)
            }
            .onChange(of: model.config.logoStrength) { _, _ in
                model.schedulePreview()
            }

            HStack(spacing: 10) {
                CircleControl(label: "Pixels", isSelected: true) {
                    model.config.cellShape = model.config.cellShape.next
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    LatticeGlyph(shape: model.config.cellShape)
                }

                CircleControl(label: "Eyes", isSelected: true) {
                    model.config.finderStyle = model.config.finderStyle.next
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    FinderGlyph(style: model.config.finderStyle)
                }

                CircleControl(label: "Centre",
                              isSelected: model.config.showsEmblem,
                              isEnabled: model.silhouette != nil) {
                    model.config.showsEmblem.toggle()
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    ZStack {
                        RoundedRectangle(cornerRadius: 5, style: .continuous)
                            .strokeBorder(Theme.primary, lineWidth: 1.6)
                            .frame(width: 21, height: 21)
                        Circle()
                            .fill(model.config.showsEmblem ? Theme.primary : Theme.tertiary)
                            .frame(width: 8, height: 8)
                    }
                }

                CircleControl(label: "Motion", isSelected: true) {
                    model.choreography = model.choreography.next
                    model.replayResolve()
                } glyph: {
                    MotionGlyph(choreography: model.choreography)
                }
            }
        }
    }
}

/// A small mark that hints at the selected choreography.
struct MotionGlyph: View {
    let choreography: Choreography

    var body: some View {
        switch choreography {
        case .scanline:
            VStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Capsule().fill(Theme.primary.opacity(index == 0 ? 1 : 0.4))
                        .frame(width: 20, height: 2.5)
                }
            }
        case .radial:
            ZStack {
                Circle().strokeBorder(Theme.primary.opacity(0.35), lineWidth: 1.5).frame(width: 22, height: 22)
                Circle().fill(Theme.primary).frame(width: 8, height: 8)
            }
        case .diagonal:
            Path { path in
                path.move(to: CGPoint(x: 0, y: 20))
                path.addLine(to: CGPoint(x: 20, y: 0))
            }
            .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .frame(width: 20, height: 20)
        case .spiral:
            Circle()
                .trim(from: 0.06, to: 0.8)
                .stroke(Theme.primary, style: StrokeStyle(lineWidth: 2.2, lineCap: .round))
                .frame(width: 20, height: 20)
        case .develop:
            LatticeGlyph(shape: .dot, colour: Theme.primary)
        case .structureFirst:
            FinderGlyph(style: .rounded)
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
    /// Cycles the user-facing orders only.
    var next: Choreography {
        let all = Choreography.selectable
        guard let index = all.firstIndex(of: self) else { return all[0] }
        return all[(index + 1) % all.count]
    }
}
