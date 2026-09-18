import CoreGraphics
import Observation
import SwiftUI

/// `CGImage` is immutable once created and documented as safe to read from any
/// thread; this box states that explicitly so images can cross to the renderer.
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

enum Stage: Int, CaseIterable {
    case input, tune, verify, export

    var title: String {
        switch self {
        case .input: return "Input"
        case .tune: return "Tune"
        case .verify: return "Verify"
        case .export: return "Export"
        }
    }
}

/// Everything the app knows, in one place.
///
/// The screens are thin: they read state and call one of the intents below.
/// Nothing renders on the main thread, and nothing reaches the preview that has
/// not come back from the planner.
@Observable
@MainActor
final class AppModel {

    // MARK: Input

    var urlText: String = "" {
        didSet { if urlText != oldValue { urlDidChange() } }
    }
    private(set) var resolvedURL: URL?
    private(set) var lengthNotice: String?
    private(set) var symbolVersion: Int?

    private(set) var logo: SendableImage?
    private(set) var logoName: String?
    private(set) var silhouette: Silhouette?
    private(set) var analysis: SilhouetteAnalysis?
    private(set) var brandColour: RGB = RGB(red: 0.365, green: 0.569, blue: 1.0)
    private(set) var logoCameFromSite = false
    private(set) var isFetchingSite = false
    private(set) var siteFetchFailed = false

    // MARK: Render

    var config = RenderConfig()
    var choreography: Choreography = .structureFirst
    private(set) var plan: RenderPlan?
    private(set) var isRendering = false
    private(set) var renderError: String?

    // MARK: Verify

    private(set) var verification: VerificationReport?
    private(set) var verifiedRender: VerifiedRender?
    private(set) var isVerifying = false
    /// Bumped whenever the symbol should play its resolve animation. The preview
    /// watches this rather than a stepped progress value, so the animation is
    /// driven by the display link instead of the main actor.
    private(set) var resolveToken = UUID()

    // MARK: Export

    private(set) var variants: [ExportVariant] = []
    private(set) var isBuildingVariants = false
    var selectedVariant: ExportVariant.Kind = .brand
    private(set) var exportBundle: ExportBundle?
    private(set) var isExporting = false
    var includeAnimation = true

    // MARK: Navigation

    var stage: Stage = .input

    private let pipeline = RenderPipeline()
    private var previewTask: Task<Void, Never>?
    private var siteTask: Task<Void, Never>?

    var accentColour: Color { brandColour.swiftUIColor }

    var canContinueFromInput: Bool {
        resolvedURL != nil && !urlText.isEmpty
    }

    // MARK: - Input intents

    private func urlDidChange() {
        let (value, url) = URLNormaliser.normalise(urlText)
        resolvedURL = url
        if let advice = URLNormaliser.lengthAdvice(for: value) {
            symbolVersion = advice.version
            lengthNotice = advice.warning
        } else {
            symbolVersion = nil
            lengthNotice = nil
        }
        siteFetchFailed = false
    }

    /// Payload actually encoded — the normalised form, so "nda.co" becomes a
    /// link rather than plain text.
    var payload: String {
        URLNormaliser.normalise(urlText).value
    }

    func setLogo(_ image: CGImage, name: String?, fromSite: Bool = false) async {
        let boxed = SendableImage(image: image)
        logo = boxed
        logoName = name
        logoCameFromSite = fromSite

        let modules = symbolVersion.map { QRVersion.size(of: $0) } ?? 33
        let extracted = await Task.detached(priority: .userInitiated) {
            let silhouette = SilhouetteExtractor.silhouette(from: boxed.image)
            let analysis = SilhouetteAnalysis.analyse(silhouette, moduleCount: modules,
                                                      subdivision: HalftonePlanner.subdivision)
            let colour = DominantColour.extract(from: boxed.image)
            return (silhouette, analysis, colour)
        }.value

        silhouette = extracted.0
        analysis = extracted.1
        if let colour = extracted.2 {
            brandColour = colour
        }
        schedulePreview()
    }

    func clearLogo() {
        logo = nil
        logoName = nil
        silhouette = nil
        analysis = nil
        logoCameFromSite = false
        schedulePreview()
    }

    /// Pulls an icon and theme colour from the site itself, for when the user has
    /// no logo file to hand.
    func fetchSiteArtwork() {
        guard let url = resolvedURL else { return }
        siteTask?.cancel()
        isFetchingSite = true
        siteFetchFailed = false
        siteTask = Task { [weak self] in
            let metadata = await SiteMetadataFetcher.fetch(for: url)
            guard let self, !Task.isCancelled else { return }
            if let themeColour = metadata.themeColour {
                self.brandColour = themeColour
            }
            if let iconURL = metadata.iconURL, let image = await SiteMetadataFetcher.loadIcon(at: iconURL) {
                await self.setLogo(image, name: iconURL.lastPathComponent, fromSite: true)
            } else if metadata.themeColour == nil {
                self.siteFetchFailed = true
            }
            self.isFetchingSite = false
        }
    }

    // MARK: - Render intents

    /// Coalesces rapid changes — a slider drag produces one render, not sixty.
    ///
    /// `animate` is for the moments worth a beat of motion: generating for the
    /// first time, or landing on a verified result. Slider tweaks re-render
    /// silently, because replaying the sequence on every frame of a drag would be
    /// unusable.
    func schedulePreview(debounce: Duration = .milliseconds(70), animate: Bool = false) {
        guard !payload.isEmpty, resolvedURL != nil else { return }
        previewTask?.cancel()
        let payload = payload
        let silhouette = silhouette
        let config = config
        let palette = currentPalette
        previewTask = Task { [weak self] in
            try? await Task.sleep(for: debounce)
            guard !Task.isCancelled, let self else { return }
            self.isRendering = true
            defer { self.isRendering = false }
            do {
                let plan = try await self.pipeline.preview(payload: payload, silhouette: silhouette,
                                                           config: config, palette: palette)
                guard !Task.isCancelled else { return }
                self.plan = plan
                self.renderError = nil
                if animate { self.resolveToken = UUID() }
            } catch is CancellationError {
                return
            } catch {
                self.renderError = error.localizedDescription
            }
        }
    }

    var currentPalette: Palette {
        ExportVariant.Kind.brand.palette(brand: brandColour)
    }

    // MARK: - Verify intents

    /// Renders, verifies, and steps back until it scans — then plays the result
    /// in. Nothing is shown that has not decoded.
    func runVerification() async {
        guard !payload.isEmpty else { return }
        isVerifying = true
        verification = nil
        defer { isVerifying = false }

        do {
            let result = try await pipeline.render(payload: payload, silhouette: silhouette,
                                                   config: config, palette: currentPalette)
            verifiedRender = result
            plan = result.plan
            verification = result.report
            config = result.config
            resolveToken = UUID()
        } catch {
            renderError = error.localizedDescription
        }
    }

    /// Replays the resolve animation, for when the user picks another
    /// choreography and wants to see it run.
    func replayResolve() {
        resolveToken = UUID()
    }

    // MARK: - Export intents

    /// Plans and verifies all four finishes at once so the user only ever picks
    /// between codes that work.
    func buildVariants() async {
        guard let base = verifiedRender else { return }
        isBuildingVariants = true
        defer { isBuildingVariants = false }

        let payload = payload
        let silhouette = silhouette
        let config = base.config
        let brand = brandColour

        var built: [ExportVariant] = []
        for kind in ExportVariant.Kind.allCases {
            let palette = kind.palette(brand: brand)
            do {
                let result = try await pipeline.render(payload: payload, silhouette: silhouette,
                                                       config: config, palette: palette)
                built.append(ExportVariant(id: kind, plan: result.plan,
                                           report: result.report, wasReduced: result.wasReduced))
            } catch {
                continue  // a finish that cannot be verified is simply not offered
            }
        }
        variants = built
        if !built.contains(where: { $0.kind == selectedVariant }), let first = built.first {
            selectedVariant = first.kind
        }
    }

    var selected: ExportVariant? {
        variants.first { $0.kind == selectedVariant }
    }

    /// Drops the written files when the chosen finish changes.
    func clearExport() {
        exportBundle = nil
    }

    func export() async {
        guard let variant = selected else { return }
        isExporting = true
        defer { isExporting = false }

        let includeAnimation = includeAnimation
        let choreography = choreography
        let plan = variant.plan
        let animation: Data? = includeAnimation
            ? await Task.detached(priority: .userInitiated) {
                var settings = AnimationExporter.Settings()
                settings.choreography = choreography
                return AnimationExporter.gif(for: plan, settings: settings)
            }.value
            : nil

        do {
            exportBundle = try ExportWriter.write(variant: variant,
                                                  basename: ExportWriter.sanitise(payload),
                                                  animation: animation)
        } catch {
            renderError = error.localizedDescription
        }
    }

    // MARK: - Navigation

    func advance() {
        switch stage {
        case .input:
            stage = .tune
            schedulePreview(debounce: .zero, animate: true)
        case .tune:
            stage = .verify
        case .verify:
            stage = .export
        case .export:
            break
        }
    }

    func back() {
        guard let previous = Stage(rawValue: stage.rawValue - 1) else { return }
        stage = previous
    }

    func startOver() {
        previewTask?.cancel()
        siteTask?.cancel()
        urlText = ""
        clearLogo()
        config = RenderConfig()
        plan = nil
        verification = nil
        verifiedRender = nil
        variants = []
        exportBundle = nil
        stage = .input
    }
}
