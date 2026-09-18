import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Step one: the artwork and the address. Two decisions, nothing else.
struct InputScreen: View {
    @Bindable var model: AppModel

    @State private var isImporting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isTargeted = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                dropZone
                urlField
                advisories
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 4)
            .padding(.bottom, 32)
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

    // MARK: - Mark

    private var dropZone: some View {
        VStack(alignment: .leading, spacing: 14) {
            ZStack {
                RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous)
                    .fill(Theme.elevated)

                if let logo = model.logo {
                    Image(decorative: logo.image, scale: 1, orientation: .up)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .padding(34)
                } else {
                    VStack(spacing: 14) {
                        LatticeGlyph(shape: .square, colour: Theme.tertiary)
                            .scaleEffect(1.7)
                            .frame(height: 34)
                        VStack(spacing: 5) {
                            Text("Drop your logo")
                                .font(.system(size: 17, weight: .medium))
                                .foregroundStyle(Theme.secondary)
                            Text("PNG · SVG · PDF · JPEG")
                                .railLabelStyle()
                        }
                    }
                }
            }
            .frame(height: 260)
            .frame(maxWidth: .infinity)
            .hairlineBorder(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous),
                            colour: isTargeted ? model.accentColour : Theme.hairline)
            .contentShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
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
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .padding(.horizontal, 16)
                        .frame(height: 38)
                        .background(Capsule().fill(Color.white.opacity(0.06)))
                        .hairlineBorder(Capsule())
                }
                if model.logo != nil {
                    Button("Clear") { model.clearLogo() }
                        .buttonStyle(SmallButtonStyle())
                }
                Spacer(minLength: 0)
            }
        }
    }

    // MARK: - Destination

    private var urlField: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            .padding(.horizontal, 18)
            .frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(Theme.elevated))
            .hairlineBorder(RoundedRectangle(cornerRadius: 18, style: .continuous),
                            colour: urlFocused ? model.accentColour.opacity(0.6) : Theme.hairline)
            .animation(.easeOut(duration: 0.14), value: urlFocused)

            if let version = model.symbolVersion {
                ValueRow(key: "Symbol",
                         value: "v\(version) · \(QRVersion.size(of: version)) modules",
                         tint: Theme.secondary)
            }
        }
    }

    // MARK: - Advisories

    @ViewBuilder
    private var advisories: some View {
        if let analysis = model.analysis, !analysis.isUsable {
            note(title: analysis.headline, body: analysis.advice, tone: Theme.caution) {
                VStack(spacing: 9) {
                    ValueRow(key: "Ink coverage", value: percent(analysis.inkCoverage))
                    ValueRow(key: "Stroke survival", value: percent(analysis.strokeSurvival))
                    ValueRow(key: "Edge density", value: percent(analysis.edgeDensity))
                }
                .padding(15)
                .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Theme.elevated))
                .hairlineBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }

        if let notice = model.lengthNotice {
            note(title: "Long destination", body: notice, tone: Theme.caution) { EmptyView() }
        }

        if model.logo == nil, model.resolvedURL != nil {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("No mark yet").railLabelStyle()
                    Text("Pull the icon and colour from the site")
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                }
                Spacer(minLength: 8)
                Button(model.isFetchingSite ? "Fetching" : "Fetch") {
                    model.fetchSiteArtwork()
                }
                .buttonStyle(SmallButtonStyle())
                .disabled(model.isFetchingSite)
            }
            if model.siteFetchFailed {
                Text("Nothing usable on that page. Upload a mark instead.")
                    .font(.system(size: 13))
                    .foregroundStyle(Theme.tertiary)
            }
        } else if model.logoCameFromSite {
            Text("Mark taken from the site").railLabelStyle()
        }
    }

    private func note<Extra: View>(title: String, body text: String, tone: Color,
                                   @ViewBuilder extra: () -> Extra) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Capsule().fill(tone).frame(width: 2.5)
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).railLabelStyle(tone)
                    Text(text)
                        .font(.system(size: 14))
                        .foregroundStyle(Theme.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            extra()
        }
    }

    private func percent(_ value: Double) -> String {
        String(format: "%.1f%%", value * 100)
    }
}
