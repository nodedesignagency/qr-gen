import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Step one: the mark and the address.
///
/// The upload panel is a contained surface with one focal chip, a title, a
/// helper line and its action inside it — not an empty box with text floating in
/// the middle. Once a mark is loaded it collapses to a file row that carries the
/// silhouette verdict, so artwork that will not survive halftoning is called out
/// here rather than three screens later.
struct InputScreen: View {
    @Bindable var model: AppModel

    @State private var isImporting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isTargeted = false
    @State private var showsDetail = false
    @FocusState private var urlFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if model.logo == nil {
                    UploadPanel(isTargeted: isTargeted,
                                accent: model.accentColour,
                                onChoose: { isImporting = true },
                                photoItem: $photoItem)
                        .dropDestination(for: Data.self) { items, _ in
                            guard let data = items.first,
                                  let image = ImageDecoder.decode(data) else { return false }
                            Task { await model.setLogo(image, name: "Dropped mark") }
                            return true
                        } isTargeted: { isTargeted = $0 }
                        .animation(.easeOut(duration: 0.14), value: isTargeted)
                } else {
                    markRow
                    if let analysis = model.analysis, !analysis.isUsable, showsDetail {
                        adviceCard(analysis)
                    }
                }

                if model.logo == nil, model.resolvedURL != nil {
                    siteFallbackRow
                }

                destinationField
                    .padding(.top, 6)
            }
            .padding(.horizontal, Theme.gutter)
            .padding(.top, 2)
            .padding(.bottom, 28)
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
                await model.setLogo(image, name: "From Photos")
            }
        }
        .onChange(of: model.analysis?.verdict) { _, verdict in
            // Open the explanation the first time a mark comes back weak.
            showsDetail = verdict != nil && verdict != .good
        }
    }

    // MARK: - The loaded mark

    private var markRow: some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                SilhouetteThumbnail(silhouette: model.silhouette)
                    .frame(width: 44, height: 44)

                // The status sits on its own line rather than competing with the
                // filename for width — a long name and a long verdict cannot
                // both fit on one row.
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.logoName ?? "Mark")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.primary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let analysis = model.analysis {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(analysis.isUsable ? Theme.positive : Theme.caution)
                                .frame(width: 5, height: 5)
                            Text(analysis.shortStatus)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(analysis.isUsable ? Theme.positive : Theme.caution)
                            if !analysis.isUsable {
                                Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(Theme.tertiary)
                            }
                        }
                    }
                }

                Spacer(minLength: 8)

                Button {
                    model.clearLogo()
                    showsDetail = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.tertiary)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Color.white.opacity(0.06)))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
            .hairlineBorder(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .onTapGesture {
                guard model.analysis?.isUsable == false else { return }
                showsDetail.toggle()
            }

            HStack(spacing: 10) {
                Button("Replace") { isImporting = true }
                    .buttonStyle(SmallButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Photos").smallButtonLabel()
                }
                Spacer(minLength: 0)
                if model.logoCameFromSite {
                    Text("From the site").railLabelStyle()
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: showsDetail)
    }

    private func adviceCard(_ analysis: SilhouetteAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            Text(analysis.headline)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(Theme.primary)
            Text(analysis.advice)
                .font(.system(size: 13))
                .foregroundStyle(Theme.secondary)
                .fixedSize(horizontal: false, vertical: true)
            Hairline()
            VStack(spacing: 9) {
                MeterRow(label: "Ink coverage", value: analysis.inkCoverage,
                         safe: 0.05...0.95)
                MeterRow(label: "Stroke survival", value: analysis.strokeSurvival,
                         safe: 0.45...1.0)
                MeterRow(label: "Fine detail", value: analysis.edgeDensity,
                         safe: 0.0...0.12)
            }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
        .hairlineBorder(RoundedRectangle(cornerRadius: 20, style: .continuous),
                        colour: Theme.caution.opacity(0.28))
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Destination

    private var destinationField: some View {
        VStack(alignment: .leading, spacing: 11) {
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
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(Theme.positive)
                        .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 18)
            .frame(height: Theme.controlHeight)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
            .hairlineBorder(RoundedRectangle(cornerRadius: 20, style: .continuous),
                            colour: urlFocused ? model.accentColour.opacity(0.55) : Theme.hairline)
            .animation(.easeOut(duration: 0.14), value: urlFocused)
            .animation(.easeOut(duration: 0.14), value: model.resolvedURL)

            if let version = model.symbolVersion {
                HStack(spacing: 8) {
                    Text("v\(version) · \(QRVersion.size(of: version)) modules")
                        .font(.valueLabel)
                        .foregroundStyle(Theme.tertiary)
                    Spacer()
                    if let notice = model.lengthNotice {
                        Text(notice)
                            .font(.system(size: 12))
                            .foregroundStyle(Theme.caution)
                            .lineLimit(2)
                            .multilineTextAlignment(.trailing)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Site fallback

    private var siteFallbackRow: some View {
        Button {
            model.fetchSiteArtwork()
        } label: {
            HStack(spacing: 13) {
                Image(systemName: model.isFetchingSite ? "arrow.triangle.2.circlepath" : "globe")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(model.accentColour)
                    .frame(width: 34, height: 34)
                    .background(Circle().fill(model.accentColour.opacity(0.12)))
                VStack(alignment: .leading, spacing: 2) {
                    Text(model.isFetchingSite ? "Reading the site…" : "Use the site's own icon")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.primary)
                    Text(model.siteFetchFailed
                         ? "Nothing usable found — add a file instead"
                         : "Pulls the icon and brand colour")
                        .font(.system(size: 12))
                        .foregroundStyle(model.siteFetchFailed ? Theme.caution : Theme.tertiary)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Theme.tertiary)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 20, style: .continuous).fill(Theme.elevated))
            .hairlineBorder(RoundedRectangle(cornerRadius: 20, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(model.isFetchingSite)
    }
}

// MARK: - Upload panel

/// The empty state: one focal chip, a title, a helper line, and the action
/// inside the panel rather than floating beneath it.
struct UploadPanel: View {
    let isTargeted: Bool
    let accent: Color
    let onChoose: () -> Void
    @Binding var photoItem: PhotosPickerItem?

    var body: some View {
        VStack(spacing: 0) {
            Button(action: onChoose) {
                VStack(spacing: 0) {
                    RoundedRectangle(cornerRadius: 21, style: .continuous)
                        .fill(accent)
                        .frame(width: 66, height: 66)
                        .overlay {
                            Image(systemName: "plus")
                                .font(.system(size: 25, weight: .semibold))
                                .foregroundStyle(.white)
                        }
                        .padding(.bottom, 20)

                    Text("Add your logo")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(Theme.primary)
                        .padding(.bottom, 6)

                    Text("PNG, SVG or PDF")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.secondary)
                        .padding(.bottom, 2)

                    Text("A solid mark holds its shape best")
                        .font(.system(size: 13))
                        .foregroundStyle(Theme.tertiary)
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Button("Choose file", action: onChoose)
                    .buttonStyle(SmallButtonStyle())
                PhotosPicker(selection: $photoItem, matching: .images) {
                    Text("Photos").smallButtonLabel()
                }
            }
            .padding(.top, 22)
        }
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background {
            ZStack {
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(Theme.elevated)
                // A single soft bloom behind the chip, so the panel reads as lit
                // from within rather than as a flat grey box.
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .fill(
                        RadialGradient(colors: [accent.opacity(isTargeted ? 0.26 : 0.13), .clear],
                                       center: .init(x: 0.5, y: 0.26),
                                       startRadius: 0, endRadius: 190)
                    )
            }
        }
        .hairlineBorder(RoundedRectangle(cornerRadius: 30, style: .continuous),
                        colour: isTargeted ? accent : Theme.hairlineStrong)
    }
}

// MARK: - Pieces

/// Draws the silhouette the planner will actually consume, at thumbnail size.
///
/// Showing the raw artwork here would be a lie — a white mark on transparency
/// would vanish, and a photo would look nothing like what gets halftoned. This
/// is the real input to the algorithm.
struct SilhouetteThumbnail: View {
    let silhouette: Silhouette?
    var resolution: Int = 26

    var body: some View {
        Canvas { context, size in
            let cell = size.width / Double(resolution)
            guard let silhouette else { return }
            var path = Path()
            for y in 0..<resolution {
                for x in 0..<resolution {
                    let u = (Double(x) + 0.5) / Double(resolution)
                    let v = (Double(y) + 0.5) / Double(resolution)
                    guard silhouette.sampleFitted(u: u, v: v, padding: 0.08) >= 0.5 else { continue }
                    path.addRect(CGRect(x: Double(x) * cell + cell * 0.1,
                                        y: Double(y) * cell + cell * 0.1,
                                        width: cell * 0.8, height: cell * 0.8))
                }
            }
            context.fill(path, with: .color(Theme.primary))
        }
        .padding(7)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(Color.white.opacity(0.05)))
        .hairlineBorder(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// A labelled bar showing where a measurement sits against its safe band.
struct MeterRow: View {
    let label: String
    let value: Double
    let safe: ClosedRange<Double>

    private var isSafe: Bool { safe.contains(value) }

    var body: some View {
        HStack(spacing: 12) {
            Text(label)
                .font(.system(size: 12))
                .foregroundStyle(Theme.secondary)
                .frame(width: 104, alignment: .leading)
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.white.opacity(0.07)).frame(height: 4)
                    Capsule()
                        .fill(isSafe ? Theme.positive : Theme.caution)
                        .frame(width: max(3, geometry.size.width * min(max(value, 0), 1)), height: 4)
                }
                .frame(height: 4)
                .frame(maxHeight: .infinity)
            }
            .frame(height: 12)
            Text(String(format: "%.0f%%", value * 100))
                .font(.mono(11))
                .foregroundStyle(isSafe ? Theme.secondary : Theme.caution)
                .frame(width: 38, alignment: .trailing)
        }
    }
}

extension Text {
    /// Matches `SmallButtonStyle` for controls that are not Buttons, such as
    /// `PhotosPicker`, which does not take a ButtonStyle reliably.
    func smallButtonLabel() -> some View {
        font(.system(size: 14, weight: .medium))
            .foregroundStyle(Theme.primary)
            .padding(.horizontal, 16)
            .frame(height: 38)
            .background(Capsule().fill(Color.white.opacity(0.06)))
            .hairlineBorder(Capsule())
    }
}
