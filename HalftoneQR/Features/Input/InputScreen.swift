import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Step one: the artwork and the address.
struct InputScreen: View {
    @Bindable var model: AppModel

    @State private var isImporting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isTargeted = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                dropZone
                urlField
                if let analysis = model.analysis, !analysis.isUsable {
                    warning(analysis)
                }
                if let notice = model.lengthNotice {
                    lengthNotice(notice)
                }
                sourceHint
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 8)
            .padding(.bottom, 40)
        }
        .scrollDismissesKeyboard(.interactively)
        .fileImporter(isPresented: $isImporting,
                      allowedContentTypes: ImageDecoder.supportedTypes,
                      allowsMultipleSelection: false) { result in
            guard case .success(let urls) = result, let url = urls.first else { return }
            Task {
                if let image = await ImageDecoder.load(contentsOf: url) {
                    await model.setLogo(image, name: url.lastPathComponent)
                }
            }
        }
        .onChange(of: photoItem) { _, item in
            guard let item else { return }
            Task {
                guard let data = try? await item.loadTransferable(type: Data.self),
                      let image = ImageDecoder.decode(data) else { return }
                await model.setLogo(image, name: "Photo")
            }
        }
    }

    // MARK: - Drop zone

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Mark").railLabelStyle()

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Theme.sunken)

                if let logo = model.logo {
                    Image(decorative: logo.image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(26)
                } else {
                    VStack(spacing: 10) {
                        ShapeGlyph(shape: .square)
                            .stroke(Theme.tertiary, lineWidth: 1)
                            .frame(width: 22, height: 22)
                        Text("Drop a logo")
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(Theme.secondary)
                        Text("PNG · SVG · PDF · JPEG")
                            .railLabelStyle()
                    }
                }
            }
            .frame(height: 190)
            .frame(maxWidth: .infinity)
            .hairlineBorder(RoundedRectangle(cornerRadius: 18, style: .continuous),
                            colour: isTargeted ? model.accentColour : Theme.hairline)
            .contentShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .onTapGesture { isImporting = true }
            .dropDestination(for: Data.self) { items, _ in
                guard let data = items.first, let image = ImageDecoder.decode(data) else { return false }
                Task { await model.setLogo(image, name: "Dropped mark") }
                return true
            } isTargeted: { isTargeted = $0 }
            .animation(.easeOut(duration: 0.14), value: isTargeted)

            HStack(spacing: 10) {
                Button("Choose file") { isImporting = true }
                    .buttonStyle(SmallButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Photos")
                }
                .buttonStyle(SmallButtonStyle())
                if model.logo != nil {
                    Button("Clear") { model.clearLogo() }
                        .buttonStyle(SmallButtonStyle())
                }
                Spacer()
                if let name = model.logoName {
                    Text(name)
                        .font(.railLabel)
                        .foregroundStyle(Theme.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }
        }
    }

    // MARK: - URL

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Destination").railLabelStyle()
            HStack(spacing: 10) {
                TextField("nodedesignagency.com", text: $model.urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($urlFocused)
                    .font(.mono(15))
                    .foregroundStyle(Theme.primary)
                    .tint(model.accentColour)
                if model.resolvedURL != nil {
                    Circle().fill(Theme.positive).frame(width: 6, height: 6)
                }
            }
            .padding(.horizontal, 16)
            .frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.sunken))
            .hairlineBorder(RoundedRectangle(cornerRadius: 14, style: .continuous),
                            colour: urlFocused ? model.accentColour.opacity(0.55) : Theme.hairline)
            .animation(.easeOut(duration: 0.14), value: urlFocused)

            if let version = model.symbolVersion {
                ValueRow(key: "Symbol", value: "v\(version) · \(QRVersion.size(of: version)) modules",
                         tint: Theme.secondary)
            }
        }
    }

    // MARK: - Advisories

    private func lengthNotice(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Rectangle().fill(Theme.caution).frame(width: 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("Long destination").railLabelStyle(Theme.caution)
                Text(text)
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.vertical, 2)
    }

    private func warning(_ analysis: SilhouetteAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                Rectangle().fill(Theme.caution).frame(width: 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(analysis.headline).railLabelStyle(Theme.caution)
                    Text(analysis.advice)
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            VStack(spacing: 8) {
                ValueRow(key: "Ink coverage", value: percent(analysis.inkCoverage))
                ValueRow(key: "Stroke survival", value: percent(analysis.strokeSurvival))
                ValueRow(key: "Edge density", value: percent(analysis.edgeDensity))
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.sunken))
            .hairlineBorder(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }

    // MARK: - Site fallback

    @ViewBuilder
    private var sourceHint: some View {
        if model.logo == nil, model.resolvedURL != nil {
            VStack(alignment: .leading, spacing: 10) {
                Hairline()
                HStack {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("No mark yet").railLabelStyle()
                        Text("Pull the icon and theme colour from the site")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.secondary)
                    }
                    Spacer()
                    Button(model.isFetchingSite ? "Fetching" : "Fetch") {
                        model.fetchSiteArtwork()
                    }
                    .buttonStyle(SmallButtonStyle())
                    .disabled(model.isFetchingSite)
                }
                if model.siteFetchFailed {
                    Text("Nothing usable found on that page. Upload a mark instead.")
                        .font(.system(size: 12))
                        .foregroundStyle(Theme.tertiary)
                }
            }
        } else if model.logoCameFromSite {
            Text("Mark taken from the site")
                .railLabelStyle()
        }
    }
}

/// The quiet secondary button used throughout.
struct SmallButtonStyle: ButtonStyle {
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(isEnabled ? Theme.primary : Theme.tertiary)
            .padding(.horizontal, 14)
            .frame(height: 34)
            .background(Capsule().fill(Color.white.opacity(configuration.isPressed ? 0.10 : 0.05)))
            .hairlineBorder(Capsule())
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
