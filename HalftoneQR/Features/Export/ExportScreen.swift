import SwiftUI

/// Step four: four finishes, each independently verified, then the files.
struct ExportScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            QRCard(plan: model.selected?.plan ?? model.plan,
                   animationKey: model.resolveToken,
                   choreography: model.choreography)
                .padding(.horizontal, Theme.gutter)
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                HStack {
                    if model.isBuildingVariants {
                        StatusPill(text: "Verifying four finishes", tone: .working)
                    } else if let variant = model.selected {
                        StatusPill(text: "Verified · \(variant.report.summary)", tone: .good)
                    }
                    Spacer()
                    if let variant = model.selected {
                        Text(variant.kind.subtitle)
                            .font(.railLabel)
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                if let bundle = model.exportBundle {
                    ShareLink(items: bundle.allURLs) {
                        HStack(spacing: 9) {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 14, weight: .semibold))
                            Text(bundle.animationURL != nil
                                 ? "Share · PNG SVG PDF GIF" : "Share · PNG SVG PDF")
                                .font(.system(size: 14, weight: .medium))
                        }
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .hairlineBorder(Capsule())
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.gutter)
        }
        .task {
            if model.variants.isEmpty {
                await model.buildVariants()
            }
        }
    }
}

/// Variant chooser and the animation toggle, in the bottom bar.
struct ExportControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 18) {
            HStack(spacing: 10) {
                if model.variants.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        VStack(spacing: 9) {
                            Circle().fill(Color.white.opacity(0.035))
                                .frame(width: Theme.circleControl, height: Theme.circleControl)
                            Text(" ").font(.controlLabel)
                        }
                        .frame(maxWidth: .infinity)
                    }
                } else {
                    ForEach(model.variants) { variant in
                        CircleControl(label: variant.kind.title,
                                      isSelected: model.selectedVariant == variant.kind) {
                            model.selectedVariant = variant.kind
                            model.clearExport()
                        } glyph: {
                            VariantSwatch(palette: variant.plan.palette)
                                .frame(width: 26, height: 26)
                        }
                    }
                }
            }
            .animation(.easeOut(duration: 0.16), value: model.selectedVariant)
            .animation(.easeOut(duration: 0.16), value: model.variants.count)

            Toggle(isOn: $model.includeAnimation) {
                Text("Include resolve animation")
                    .font(.system(size: 14))
                    .foregroundStyle(Theme.secondary)
            }
            .toggleStyle(HairlineToggleStyle())
        }
    }
}

/// A miniature of the palette a variant will use.
struct VariantSwatch: View {
    let palette: Palette

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .fill(palette.paper.swiftUIColor)
            VStack(spacing: 2.5) {
                HStack(spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 1.5).fill(palette.structure.swiftUIColor)
                        .frame(width: 7, height: 7)
                    RoundedRectangle(cornerRadius: 1).fill(palette.art.swiftUIColor)
                        .frame(width: 4, height: 4)
                }
                HStack(spacing: 2.5) {
                    RoundedRectangle(cornerRadius: 1).fill(palette.art.swiftUIColor)
                        .frame(width: 4, height: 4)
                    RoundedRectangle(cornerRadius: 1).fill(palette.ink.swiftUIColor)
                        .frame(width: 5, height: 5)
                }
            }
        }
        .hairlineBorder(RoundedRectangle(cornerRadius: 7, style: .continuous),
                        colour: .black.opacity(0.12))
    }
}

/// A toggle drawn as a hairline switch rather than the system control, so it
/// sits with everything else.
struct HairlineToggleStyle: ToggleStyle {
    @Environment(\.signalAccent) private var accent

    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn.toggle()
        } label: {
            HStack {
                configuration.label
                Spacer()
                Capsule()
                    .fill(configuration.isOn ? accent : Color.white.opacity(0.10))
                    .frame(width: 42, height: 25)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Theme.primary)
                            .frame(width: 19, height: 19)
                            .padding(3)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: configuration.isOn)
    }
}
