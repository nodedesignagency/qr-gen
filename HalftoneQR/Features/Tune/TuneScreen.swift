import SwiftUI

/// Step two: one slider, three shapes, and the symbol itself doing the talking.
struct TuneScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            QRPreview(plan: model.plan, choreography: model.choreography)
                .padding(.horizontal, 32)
                .frame(maxHeight: .infinity)

            readout
                .padding(.horizontal, Theme.gutter)
                .padding(.bottom, 10)
        }
    }

    private var readout: some View {
        HStack(spacing: 14) {
            if model.isRendering {
                StatusPill(text: "Rendering", tone: .working)
            } else if let plan = model.plan {
                StatusPill(text: "v\(plan.version) · mask \(plan.mask)", tone: .neutral)
            }
            Spacer()
            if let plan = model.plan {
                Text("\(plan.moduleCount)×\(plan.moduleCount)")
                    .font(.railLabel)
                    .foregroundStyle(Theme.tertiary)
            }
        }
    }
}

/// The tune screen's controls, which live in the bottom bar.
struct TuneControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            TechSlider(title: "Logo strength", value: $model.config.logoStrength) { editing in
                model.schedulePreview(debounce: editing ? .milliseconds(40) : .zero)
            }
            .onChange(of: model.config.logoStrength) { _, _ in
                model.schedulePreview()
            }

            ShapePicker(selection: $model.config.cellShape)
                .onChange(of: model.config.cellShape) { _, _ in
                    model.schedulePreview(debounce: .zero)
                }

            HStack(spacing: 8) {
                ForEach(FinderStyle.allCases) { style in
                    Button {
                        model.config.finderStyle = style
                        model.schedulePreview(debounce: .zero)
                    } label: {
                        Text(style.label)
                            .railLabelStyle(model.config.finderStyle == style
                                            ? Theme.primary : Theme.tertiary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 9)
                            .background(
                                RoundedRectangle(cornerRadius: 9, style: .continuous)
                                    .fill(model.config.finderStyle == style
                                          ? Color.white.opacity(0.05) : .clear))
                            .hairlineBorder(RoundedRectangle(cornerRadius: 9, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    model.config.showsEmblem.toggle()
                    model.schedulePreview(debounce: .zero)
                } label: {
                    Text("Centre")
                        .railLabelStyle(model.config.showsEmblem ? Theme.primary : Theme.tertiary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 9)
                        .background(
                            RoundedRectangle(cornerRadius: 9, style: .continuous)
                                .fill(model.config.showsEmblem ? Color.white.opacity(0.05) : .clear))
                        .hairlineBorder(RoundedRectangle(cornerRadius: 9, style: .continuous))
                }
                .buttonStyle(.plain)
                .disabled(model.silhouette == nil)
                .opacity(model.silhouette == nil ? 0.4 : 1)
            }
            .animation(.easeOut(duration: 0.14), value: model.config.finderStyle)
            .animation(.easeOut(duration: 0.14), value: model.config.showsEmblem)
        }
    }
}
