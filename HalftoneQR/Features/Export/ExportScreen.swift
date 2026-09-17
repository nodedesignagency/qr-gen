import SwiftUI

/// Step four: four finishes, each independently verified, then the files.
struct ExportScreen: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            QRPreview(plan: model.selected?.plan ?? model.plan,
                      choreography: model.choreography)
                .padding(.horizontal, 44)
                .frame(maxHeight: .infinity)

            VStack(spacing: 14) {
                if model.isBuildingVariants {
                    HStack {
                        StatusPill(text: "Verifying four finishes", tone: .working)
                        Spacer()
                    }
                } else if let variant = model.selected {
                    HStack {
                        StatusPill(text: "Verified · \(variant.report.summary)", tone: .good)
                        Spacer()
                        Text(variant.kind.subtitle)
                            .font(.railLabel)
                            .foregroundStyle(Theme.tertiary)
                    }
                }

                if let bundle = model.exportBundle {
                    ShareLink(items: bundle.allURLs) {
                        HStack(spacing: 8) {
                            Text("Share \(bundle.allURLs.count) files")
                            Text(bundle.animationURL != nil ? "PNG · SVG · PDF · GIF" : "PNG · SVG · PDF")
                                .railLabelStyle(Theme.tertiary)
                        }
                    }
                    .buttonStyle(SmallButtonStyle())
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.bottom, 10)
        }
        .task {
            if model.variants.isEmpty {
                await model.buildVariants()
            }
        }
    }
}

/// Variant chooser and the export trigger, in the bottom bar.
struct ExportControls: View {
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 16) {
            HStack(spacing: 8) {
                ForEach(model.variants) { variant in
                    Button {
                        model.selectedVariant = variant.kind
                        model.clearExport()
                    } label: {
                        VStack(spacing: 8) {
                            VariantSwatch(palette: variant.plan.palette)
                                .frame(height: 30)
                            Text(variant.kind.title)
                                .railLabelStyle(model.selectedVariant == variant.kind
                                                ? Theme.primary : Theme.tertiary)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(model.selectedVariant == variant.kind
                                      ? Color.white.opacity(0.05) : .clear))
                        .hairlineBorder(RoundedRectangle(cornerRadius: 12, style: .continuous),
                                        colour: model.selectedVariant == variant.kind
                                        ? Theme.hairlineStrong : Theme.hairline)
                    }
                    .buttonStyle(.plain)
                }
                if model.variants.isEmpty {
                    ForEach(0..<4, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .fill(Theme.sunken)
                            .frame(height: 74)
                            .frame(maxWidth: .infinity)
                    }
                }
            }
            .animation(.easeOut(duration: 0.16), value: model.selectedVariant)
            .animation(.easeOut(duration: 0.16), value: model.variants.count)

            Toggle(isOn: $model.includeAnimation) {
                Text("Include resolve animation").railLabelStyle(Theme.secondary)
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
            HStack(spacing: 3) {
                RoundedRectangle(cornerRadius: 1.5).fill(palette.structure.swiftUIColor)
                    .frame(width: 8, height: 8)
                RoundedRectangle(cornerRadius: 1.5).fill(palette.art.swiftUIColor)
                    .frame(width: 5, height: 5)
                RoundedRectangle(cornerRadius: 1.5).fill(palette.ink.swiftUIColor)
                    .frame(width: 5, height: 5)
            }
        }
        .hairlineBorder(RoundedRectangle(cornerRadius: 7, style: .continuous))
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
                    .frame(width: 38, height: 22)
                    .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                        Circle()
                            .fill(Theme.primary)
                            .frame(width: 16, height: 16)
                            .padding(3)
                    }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .animation(.easeOut(duration: 0.14), value: configuration.isOn)
    }
}
