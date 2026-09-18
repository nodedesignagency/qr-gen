import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

/// Screen one, built to the design file — and, once the island has let go of
/// the card, the customise page too. They are one screen: the card lands in
/// the frame the page keeps for it, the inputs give way to the controls as it
/// touches down, and nothing navigates.
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

    /// The page keeps one slot. Before generating it is the upload card; from
    /// the moment the drop lets go it is the square the card will land in, so
    /// the overlay has somewhere exact to hand over to and nothing jumps. It
    /// stays while the card is drawn back, for the same reason in reverse.
    private var isCustomising: Bool {
        model.generatePhase.isMovingCard || model.verifiedRender != nil
    }

    /// The controls arrive once the symbol has formed, so the big bang has the
    /// page to itself.
    private var controlsShown: Bool {
        model.cardSettled || (model.generatePhase == .idle && model.verifiedRender != nil)
    }

    var body: some View {
        ZStack {
            AppBackground()

            VStack(spacing: 0) {
                if isCustomising {
                    customiseHeader
                        .padding(.top, 10)
                        .padding(.bottom, 16)
                } else {
                    title
                        .padding(.top, 10)
                        .padding(.bottom, 30)
                }

                cardSurface
                    .frame(maxWidth: surfaceWidth)
                    // Changing the inputs mid-sequence would pull the result out
                    // from under the animation, so they wait for it to finish.
                    .allowsHitTesting(!model.generatePhase.isRunning)

                if isCustomising {
                    customiseControls
                        .frame(maxWidth: surfaceWidth)
                        .padding(.top, 14)
                        // They rise into place as the last cells lock in.
                        .opacity(controlsShown ? 1 : 0)
                        .offset(y: controlsShown ? 0 : 28)
                        .animation(.spring(response: 0.5, dampingFraction: 0.72), value: controlsShown)
                        .allowsHitTesting(controlsShown && !model.generatePhase.isRunning)
                } else {
                    urlSurface
                        .frame(maxWidth: surfaceWidth)
                        .padding(.top, 22)
                        .allowsHitTesting(!model.generatePhase.isRunning)

                    if let analysis = model.analysis, !analysis.isUsable, showsDetail {
                        adviceSurface(analysis)
                            .frame(maxWidth: surfaceWidth)
                            .padding(.top, 16)
                    }
                }

                Spacer(minLength: 12)

                primaryButton
                    .frame(maxWidth: surfaceWidth)
                    .padding(.bottom, 24)
            }
            .padding(.horizontal, 20)
            .animation(.easeOut(duration: 0.28), value: isCustomising)
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

    /// The customise page's header: its name, and the way back to the inputs.
    /// Edit takes the card back into the island; the logo and URL stay put.
    private var customiseHeader: some View {
        HStack(alignment: .center) {
            Text("Customise")
                .snType(24, weight: .medium)
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.12), radius: 8, y: 2)
            Spacer()
            Button {
                model.withdraw()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 11, weight: .bold))
                    Text("Edit")
                        .snType(15, weight: .semibold)
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: 38)
                .glassSurface(cornerRadius: 19)
            }
            .buttonStyle(.plain)
            .disabled(model.generatePhase.isRunning)
            .opacity(model.generatePhase.isRunning ? 0.5 : 1)
        }
        .frame(height: 44)
        .frame(maxWidth: surfaceWidth)
    }

    // MARK: - Card

    @ViewBuilder
    private var cardSurface: some View {
        if isCustomising {
            ZStack {
                // While the overlay owns the card the slot is empty; the page's
                // own card takes over in the same frame once it has landed.
                if !model.generatePhase.isMovingCard, let plan = model.plan {
                    QRCard(plan: plan,
                           animationKey: model.resolveToken,
                           choreography: model.choreography,
                           isScanning: model.isVerifying,
                           cornerRadius: CGFloat(LiquidTimeline.cardRadius))
                }
            }
            .frame(width: surfaceWidth, height: surfaceWidth)
            .cardSlot()
        } else {
            Group {
                if model.logo == nil { emptyUpload } else { loadedUpload }
            }
            .frame(height: 200)
            .frame(maxWidth: .infinity)
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

    // MARK: - Customise

    /// The card's state, the slider, and the round controls. Every change
    /// re-renders a fast preview; Verify proves it before Export is offered.
    private var customiseControls: some View {
        VStack(spacing: 14) {
            statusRow

            GlassSlider(title: "Logo strength", value: $model.config.logoStrength) { editing in
                model.schedulePreview(debounce: editing ? .milliseconds(40) : .zero)
            }
            .onChange(of: model.config.logoStrength) { _, _ in
                model.schedulePreview()
            }

            HStack(spacing: 10) {
                GlassControl(label: "Pixels") {
                    model.config.cellShape = model.config.cellShape.next
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    LatticeGlyph(shape: model.config.cellShape, colour: .white)
                }

                GlassControl(label: "Eyes") {
                    model.config.finderStyle = model.config.finderStyle.next
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    FinderGlyph(style: model.config.finderStyle, colour: .white)
                }

                GlassControl(label: "Centre",
                             isSelected: model.config.showsEmblem,
                             isEnabled: model.silhouette != nil) {
                    model.config.showsEmblem.toggle()
                    model.schedulePreview(debounce: .zero)
                } glyph: {
                    EmblemGlyph(isOn: model.config.showsEmblem)
                }

                GlassControl(label: "Motion") {
                    model.choreography = model.choreography.next
                    model.replayResolve()
                } glyph: {
                    MotionGlyph(choreography: model.choreography)
                }
            }
            .padding(.top, 4)
        }
    }

    private var statusRow: some View {
        HStack(spacing: 8) {
            if let plan = model.plan {
                GlassPill(text: "V\(plan.version) · \(plan.moduleCount)×\(plan.moduleCount)")
            }
            if model.isVerifying {
                GlassPill(text: "Decoding", dot: Color(hex: "#73FAFF") ?? .cyan)
            } else if model.isVerified, let report = model.verification {
                GlassPill(text: "Verified · \(report.summary)", dot: Color(hex: "#7CFFB2") ?? .green)
            } else {
                GlassPill(text: "Edited · verify to export", dot: Color(hex: "#FFD36B") ?? .yellow)
            }
            Spacer(minLength: 0)
        }
        .animation(.easeOut(duration: 0.18), value: model.isVerifying)
        .animation(.easeOut(duration: 0.18), value: model.isVerified)
    }

    // MARK: - Action

    /// One button for the whole page: Generate, then Verify, then Export.
    private var primaryButton: some View {
        Button {
            if isCustomising {
                if model.isVerified {
                    model.advance()
                } else {
                    Task { await model.runVerification() }
                }
            } else {
                // The keyboard would sit over the landing spot, and a keystroke
                // mid-sequence would discard what is being generated.
                urlFocused = false
                Task { await model.generate() }
            }
        } label: {
            Text(buttonTitle)
                .snType(20, weight: .semibold)
                .foregroundStyle(isReady ? (Color(hex: "#0E7684") ?? .teal)
                                         : Color.white.opacity(0.7))
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background {
                    if isReady {
                        Capsule().fill(.white)
                    } else {
                        // Until there is something to do, the button stays in
                        // the glass language and solidifies once it is ready.
                        // A translucent white pill over bright water just reads
                        // as a smudge.
                        Color.clear.glassSurface(cornerRadius: 32)
                    }
                }
        }
        .buttonStyle(.plain)
        .disabled(!isReady || model.generatePhase.isRunning || model.isVerifying)
        .animation(.easeOut(duration: 0.2), value: isReady)
    }

    private var buttonTitle: String {
        switch model.generatePhase {
        case .working, .printing:
            return "Generating"
        case .retracting:
            return "Generate QR Code"
        case .idle:
            if !isCustomising { return "Generate QR Code" }
            if model.isVerifying { return "Verifying" }
            return model.isVerified ? "Export" : "Verify"
        }
    }

    private var isReady: Bool {
        isCustomising ? model.plan != nil : model.canContinueFromInput
    }
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
