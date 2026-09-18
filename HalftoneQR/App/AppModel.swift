import CoreGraphics
import Observation
import SwiftUI

/// `CGImage` is immutable once created and documented as safe to read from any
/// thread; this box states that explicitly so images can cross to the renderer.
struct SendableImage: @unchecked Sendable {
    let image: CGImage
}

enum Stage: Int, CaseIterable {
    case input, export

    var title: String {
        switch self {
        case .input: return "Input"
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
    /// Radial by default: the burst's ring is the front of this order.
    var choreography: Choreography = .radial
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

    // MARK: Generate animation

    private(set) var generatePhase: GeneratePhase = .idle
    /// The plan on the print.
    private(set) var generatingPlan: RenderPlan?
    /// Clock origin for the print timeline — and, before it, for the wait.
    private(set) var printStart: Date = .now
    /// How far the wait had swelled the drop when the print began.
    private(set) var generateCharge: Double = 0
    /// True from the moment the card touches down. The controls arrive on it.
    private(set) var cardLanded = false

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
        discardGeneratedResult()
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

        discardGeneratedResult()
        silhouette = extracted.0
        analysis = extracted.1
        if let colour = extracted.2 {
            brandColour = colour
        }
        schedulePreview()
    }

    func clearLogo() {
        discardGeneratedResult()
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

    /// Drops a generated symbol once its inputs change, so the page never shows a
    /// code that no longer matches what is on screen.
    ///
    /// On the input page the card is drawn back into the island rather than
    /// vanishing: the same sequence that produced it, run backwards.
    private func discardGeneratedResult() {
        guard let withdrawn = verifiedRender else { return }
        verifiedRender = nil
        verification = nil
        plan = nil

        // The inputs are locked while the sequence runs, so this only lands
        // mid-sequence if something changed underneath us. Stop it: `generate()`
        // checks the phase after every wait and drops a result nobody asked for.
        if generatePhase == .working || generatePhase == .printing {
            generatingPlan = nil
            generatePhase = .idle
            return
        }
        guard stage == .input, generatePhase == .idle else {
            generatingPlan = nil
            return
        }

        generatingPlan = withdrawn.plan
        printStart = .now
        cardLanded = false
        generatePhase = .retracting
        Task { [weak self] in
            // A soft tick as the drop rejoins the island.
            let merge = LiquidTimeline.retractDuration * 0.78
            try? await Task.sleep(for: .seconds(merge))
            guard let self, self.generatePhase == .retracting else { return }
            Haptics.impact(.soft, intensity: 0.4)
            try? await Task.sleep(for: .seconds(LiquidTimeline.retractDuration - merge))
            guard self.generatePhase == .retracting else { return }
            self.generatingPlan = nil
            self.generatePhase = .idle
        }
    }

    /// Takes the card back so the inputs can be edited. The logo and the URL
    /// stay; the result goes, so the next Generate runs the loop again.
    func withdraw() {
        discardGeneratedResult()
    }

    /// True while the card on the page is the one the loop proved. Any change
    /// to the controls re-renders a fast, unproven preview until Verify runs.
    var isVerified: Bool {
        guard let plan, let verifiedRender else { return false }
        return plan.id == verifiedRender.plan.id
    }

    var currentPalette: Palette {
        ExportVariant.Kind.brand.palette(brand: brandColour)
    }

    // MARK: - Generate

    /// Renders, verifies, then lets the island drop the result onto the page.
    ///
    /// The verify loop runs first, and the drop swells from the island while it
    /// does, because the loop's duration depends on the artwork and a fixed
    /// animation cannot cover a variable wait honestly. Once there is a verified
    /// symbol, one continuous timeline lets the drop go, spreads it into the
    /// card, and bursts the symbol onto it.
    ///
    /// Nothing navigates. The card lands in the frame this page already keeps for
    /// it, and the page becomes the result.
    func generate() async {
        guard canContinueFromInput, generatePhase == .idle else { return }

        let payload = payload
        let silhouette = silhouette
        let config = config
        let palette = currentPalette

        printStart = .now
        cardLanded = false
        generatePhase = .working
        Haptics.impact(.soft, intensity: 0.5)

        let result = try? await pipeline.render(payload: payload, silhouette: silhouette,
                                                config: config, palette: palette)
        guard let result, generatePhase == .working else {
            generatePhase = .idle
            if result == nil {
                renderError = RenderPipelineError.couldNotVerify.localizedDescription
                Haptics.warning()
            }
            return
        }

        verifiedRender = result
        verification = result.report
        self.config = result.config
        generatingPlan = result.plan

        // The wait swelled the drop; the print picks up from wherever it got to.
        generateCharge = LiquidTimeline.charge(afterWaiting: Date.now.timeIntervalSince(printStart))
        printStart = .now
        generatePhase = .printing

        // The haptics follow the liquid: a soft tick as the neck snaps, a firm
        // one as the card lands, a ratchet as the burst crosses the card, a
        // harder one as the finders punch in, and the success once it is done.
        await sleep(untilBeat: LiquidTimeline.breakAt)
        guard generatePhase == .printing else { return }
        Haptics.impact(.soft, intensity: 0.55)

        await sleep(untilBeat: LiquidTimeline.landAt)
        guard generatePhase == .printing else { return }
        Haptics.impact(.rigid, intensity: 0.75)
        cardLanded = true

        let burst = LiquidTimeline.developAt
        let burstSpan = LiquidTimeline.developEnd - LiquidTimeline.developAt
        for (share, intensity) in [(0.30, 0.45), (0.55, 0.6)] {
            await sleep(untilBeat: burst + share * burstSpan)
            guard generatePhase == .printing else { return }
            Haptics.impact(.light, intensity: intensity)
        }
        await sleep(untilBeat: burst + 0.8 * burstSpan)
        guard generatePhase == .printing else { return }
        Haptics.impact(.medium, intensity: 0.9)

        await sleep(untilBeat: 1)
        guard generatePhase == .printing else { return }

        // The page takes the card over at exactly the frame the overlay left it.
        plan = result.plan
        generatingPlan = nil
        generatePhase = .idle
        Haptics.success()
    }

    /// Sleeps until a beat of the print, given as a fraction of its duration.
    /// Measured from the print's start rather than accumulated, so the haptics
    /// stay on the animation however long each wait actually took.
    private func sleep(untilBeat beat: Double) async {
        let due = printStart.addingTimeInterval(beat * LiquidTimeline.duration)
        let remaining = due.timeIntervalSinceNow
        if remaining > 0 {
            try? await Task.sleep(for: .seconds(remaining))
        }
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
            Haptics.success()
        } catch {
            renderError = error.localizedDescription
            Haptics.warning()
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

    /// Only a proven card goes to export; the page's Verify button gates it.
    func advance() {
        switch stage {
        case .input:
            guard isVerified else { return }
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
        cardLanded = false
        generateCharge = 0
        stage = .input
    }
}
