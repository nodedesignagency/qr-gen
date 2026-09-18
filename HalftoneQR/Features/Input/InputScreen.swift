import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Screen one, built to the design file.
///
/// Measurements come straight from the Figma inspector: 353-wide surfaces on a
/// 393 frame (20pt margins), 20pt corner radius, `#73FAFF` at 20% over glass,
/// 21/16 padding, SN Pro Medium at 24 and 20 with -1% tracking.
struct InputScreen: View {
    @Bindable var model: AppModel

    @State private var isImporting = false
    @State private var photoItem: PhotosPickerItem?
    @State private var isTargeted = false
    @State private var showsDetail = false
    @FocusState private var urlFocused: Bool

    private let surfaceWidth: CGFloat = 353
    private let radius: CGFloat = 20

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                title
                    .padding(.top, 10)
                    .padding(.bottom, 30)

                uploadSurface
                    .frame(maxWidth: surfaceWidth)
                    .padding(.bottom, 22)

                urlSurface
                    .frame(maxWidth: surfaceWidth)

                if let analysis = model.analysis, !analysis.isUsable, showsDetail {
                    adviceSurface(analysis)
                        .frame(maxWidth: surfaceWidth)
                        .padding(.top, 16)
                }

                Spacer(minLength: 24)

                generateButton
                    .frame(maxWidth: surfaceWidth)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
        }
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
            showsDetail = verdict != nil && verdict != .good
        }
        .animation(.easeOut(duration: 0.22), value: model.logo == nil)
        .animation(.easeOut(duration: 0.22), value: showsDetail)
    }

    // MARK: - Title

    private var title: some View {
        Text("Generate New\nQR Code")
            .snType(32, weight: .medium)
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineSpacing(8)
            .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
    }

    // MARK: - Upload

    private var uploadSurface: some View {
        Group {
            if model.logo == nil { emptyUpload } else { loadedUpload }
        }
        .frame(height: 200)
        .frame(maxWidth: .infinity)
        // Only this surface carries the five inner shadows; in the design file
        // they are switched off on the URL field below.
        .glassSurface(cornerRadius: radius, innerGlow: true, isHighlighted: isTargeted)
        .onTapGesture {
            if model.logo == nil { isImporting = true }
        }
        .dropDestination(for: Data.self) { items, _ in
            guard let data = items.first, let image = ImageDecoder.decode(data) else { return false }
            Task { await model.setLogo(image, name: "Dropped mark") }
            return true
        } isTargeted: { isTargeted = $0 }
    }

    private var emptyUpload: some View {
        VStack(spacing: 10) {
            UploadMark(size: 96)
            Text("Upload Your Logo")
                .snType(24, weight: .medium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 16)
    }

    /// Once a mark is loaded the same surface shows the silhouette the planner
    /// will consume, plus its verdict. Showing the raw file would mislead: a
    /// white mark on transparency would vanish here.
    private var loadedUpload: some View {
        VStack(spacing: 10) {
            SilhouetteThumbnail(silhouette: model.silhouette)
                .frame(width: 96, height: 96)

            Text(model.logoName ?? "Your mark")
                .snType(20, weight: .medium)
                .foregroundStyle(.white)
                .lineLimit(1)
                .truncationMode(.middle)

            if let analysis = model.analysis {
                Button {
                    guard !analysis.isUsable else { return }
                    showsDetail.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Circle()
                            .fill(analysis.isUsable ? Color.white : Color(hex: "#FFD36B") ?? .yellow)
                            .frame(width: 5, height: 5)
                        Text(analysis.shortStatus)
                            .snType(14, weight: .medium)
                            .foregroundStyle(analysis.isUsable
                                             ? .white.opacity(0.75)
                                             : Color(hex: "#FFD36B") ?? .yellow)
                        if !analysis.isUsable {
                            Image(systemName: showsDetail ? "chevron.up" : "chevron.down")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(.white.opacity(0.6))
                        }
                    }
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 16)
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 8) {
                PhotosPicker(selection: $photoItem, matching: .images) {
                    surfaceIcon("photo")
                }
                Button { isImporting = true } label: { surfaceIcon("arrow.triangle.2.circlepath") }
                    .buttonStyle(.plain)
                Button {
                    model.clearLogo()
                    showsDetail = false
                } label: { surfaceIcon("xmark") }
                    .buttonStyle(.plain)
            }
            .padding(12)
        }
    }

    private func surfaceIcon(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(.white.opacity(0.85))
            .frame(width: 28, height: 28)
            .background(Circle().fill(.white.opacity(0.18)))
    }

    // MARK: - URL

    private var urlSurface: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .leading) {
                if model.urlText.isEmpty {
                    Text("Enter URL")
                        .snType(20, weight: .medium)
                        .foregroundStyle(.white.opacity(0.75))
                }
                TextField("", text: $model.urlText)
                    .snType(20, weight: .medium)
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .submitLabel(.done)
                    .focused($urlFocused)
                    .tint(.white)
            }
            if model.resolvedURL != nil {
                Image(systemName: "checkmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .transition(.scale.combined(with: .opacity))
            }
        }
        .padding(.horizontal, 21)
        .padding(.vertical, 16)
        .frame(height: 58)
        .frame(maxWidth: .infinity)
        .glassSurface(cornerRadius: radius, isHighlighted: urlFocused)
        .animation(.easeOut(duration: 0.16), value: model.resolvedURL)
        .animation(.easeOut(duration: 0.16), value: urlFocused)
    }

    // MARK: - Advice

    private func adviceSurface(_ analysis: SilhouetteAnalysis) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(analysis.headline)
                .snType(16, weight: .semibold)
                .foregroundStyle(.white)
            Text(analysis.advice)
                .snType(14, weight: .regular)
                .foregroundStyle(.white.opacity(0.8))
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 21)
        .padding(.vertical, 16)
        .glassSurface(cornerRadius: radius)
        .transition(.opacity.combined(with: .move(edge: .top)))
    }

    // MARK: - Action

    private var generateButton: some View {
        Button {
            model.advance()
        } label: {
            Text("Generate QR Code")
                .snType(20, weight: .semibold)
                .foregroundStyle(isReady ? (Color(hex: "#0E7684") ?? .teal)
                                         : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background {
                    if isReady {
                        Capsule().fill(.white)
                    } else {
                        // Until there is something to generate, the button stays
                        // in the glass language and solidifies once it is ready.
                        // A translucent white pill over bright water just reads
                        // as a smudge.
                        Color.clear.glassSurface(cornerRadius: 32)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isReady)
        .animation(.easeOut(duration: 0.2), value: isReady)
    }

    private var isReady: Bool { model.canContinueFromInput }
}

/// Draws the silhouette the planner will actually consume, at thumbnail size.
struct SilhouetteThumbnail: View {
    let silhouette: Silhouette?
    var resolution: Int = 30
    var colour: Color = .white

    var body: some View {
        Canvas { context, size in
            guard let silhouette else { return }
            let cell = size.width / Double(resolution)
            var path = Path()
            for y in 0..<resolution {
                for x in 0..<resolution {
                    let u = (Double(x) + 0.5) / Double(resolution)
                    let v = (Double(y) + 0.5) / Double(resolution)
                    guard silhouette.sampleFitted(u: u, v: v, padding: 0.06) >= 0.5 else { continue }
                    path.addRect(CGRect(x: Double(x) * cell + cell * 0.08,
                                        y: Double(y) * cell + cell * 0.08,
                                        width: cell * 0.84, height: cell * 0.84))
                }
            }
            context.fill(path, with: .color(colour))
        }
    }
}
