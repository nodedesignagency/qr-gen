import SwiftUI

/// The hero: the symbol on its paper card, big and centred with room around it.
///
/// While the resolve animation runs, the symbol is drawn live at module
/// resolution, which is cheap enough to hold a steady frame rate on the densest
/// symbol the app can make. When it finishes, the full-resolution halftone
/// bitmap takes over and the detail sharpens in rather than fading.
///
/// The animation is driven by `TimelineView` off a start date, not by stepping a
/// published value on the main actor — that stutters and drifts.
struct QRCard: View {
    let plan: RenderPlan?
    /// Changing this restarts the resolve animation.
    var animationKey: UUID?
    var choreography: Choreography = .structureFirst
    var isScanning: Bool = false
    var duration: Double = 1.15
    /// The page's card takes the radius the printed card landed with, so the
    /// hand-over is invisible; elsewhere the radius follows the card's size.
    var cornerRadius: CGFloat? = nil

    @State private var startedAt: Date?
    @State private var playedKey: UUID?
    @State private var rendered: CGImage?
    @State private var renderedPlanID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            card(side: side)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .onChange(of: animationKey) { _, key in
            guard let key, key != playedKey else { return }
            playedKey = key
            startedAt = .now
        }
        .task(id: playedKey) {
            // TimelineView(.animation) drives at the display refresh rate for as
            // long as it is on screen, so it is torn down once the run is over.
            guard playedKey != nil else { return }
            try? await Task.sleep(for: .seconds(duration + 0.1))
            guard !Task.isCancelled else { return }
            startedAt = nil
        }
        .task(id: plan?.id) {
            guard let plan else { return }
            let image = await Task.detached(priority: .userInitiated) {
                RasterRenderer.image(for: plan, pixelSize: 1200).map(SendableImage.init)
            }.value
            guard !Task.isCancelled else { return }
            rendered = image?.image
            renderedPlanID = plan.id
        }
    }

    @ViewBuilder
    private func card(side: CGFloat) -> some View {
        ZStack {
            if let plan {
                if let startedAt {
                    // Live module-resolution drawing until the sequence completes,
                    // then the bitmap takes over in the same frame position.
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        let progress = min(max(elapsed / duration, 0), 1)
                        if progress < 1 {
                            ModuleResolveCanvas(plan: plan, progress: progress,
                                                choreography: choreography)
                        } else {
                            settled(plan: plan)
                        }
                    }
                } else {
                    settled(plan: plan)
                }
            } else {
                EmptyCardPlaceholder()
            }

            if isScanning { ScanSweep() }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? side * 0.085, style: .continuous))
    }

    @ViewBuilder
    private func settled(plan: RenderPlan) -> some View {
        if let rendered, renderedPlanID == plan.id {
            Image(decorative: rendered, scale: 1, orientation: .up)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            // The bitmap is still rendering; the live canvas stands in so there
            // is never an empty frame.
            ModuleResolveCanvas(plan: plan, progress: 1, choreography: choreography)
        }
    }
}

/// Module-resolution live drawing.
///
/// Cells are grouped by how far through their landing they are, and each group
/// is filled as a single path, so a 61-module symbol costs a few path fills per
/// frame instead of several thousand. The grouping is also what lets the burst
/// colour a module by its heat without a fill per module.
struct ModuleResolveCanvas: View {
    let plan: RenderPlan
    let progress: Double
    let choreography: Choreography
    /// When set, modules land hot in this colour and cool to the ink, and a
    /// radial order draws its front as a ring. The generate animation's burst;
    /// the preview and the export leave it nil.
    var burst: RGB? = nil

    private static let buckets = 10

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let scale = size.width / plan.canvasUnits

            context.fill(Path(roundedRect: CGRect(origin: .zero, size: size),
                              cornerRadius: plan.paperCornerRadius * scale,
                              style: .continuous),
                         with: .color(plan.palette.paper.swiftUIColor))

            let count = plan.moduleCount
            let window = choreography.landingWindow
            let span = 1 - window
            var paths = [Path](repeating: Path(), count: Self.buckets)

            for y in 0..<count {
                for x in 0..<count where plan.moduleGrid[y * count + x] {
                    let isFunction = plan.functionGrid[y * count + x]
                    let delay = choreography.delay(x: x, y: y, count: count,
                                                   isFunction: isFunction) * span
                    let raw = min(max((progress - delay) / window, 0), 1)
                    guard raw > 0.02 else { continue }
                    // Quantised overshoot, matching the exported animation exactly.
                    let stepped = (raw * 4).rounded(.down) / 4
                    let landed = stepped < 0.75 ? stepped * 1.12 : 1.12 - (stepped - 0.75) * 0.48
                    let bucket = min(Int(raw * Double(Self.buckets - 1)), Self.buckets - 1)
                    let blockSize = landed * scale
                    let cx = (plan.quietZone + Double(x) + 0.5) * scale
                    let cy = (plan.quietZone + Double(y) + 0.5) * scale
                    paths[bucket].addRect(CGRect(x: cx - blockSize / 2, y: cy - blockSize / 2,
                                                 width: blockSize, height: blockSize))
                }
            }

            let ink = plan.palette.ink
            let hot = burst?.mixed(with: .paper, amount: 0.55)
            for (index, path) in paths.enumerated() where !path.isEmpty {
                var colour = ink
                if let hot {
                    // Hot as it lands, the ink once it has settled.
                    let heat = pow(1 - Double(index) / Double(Self.buckets - 1), 1.5)
                    colour = ink.mixed(with: hot, amount: heat)
                }
                context.fill(path, with: .color(colour.swiftUIColor))
            }

            // The front of a radial burst, as a ring: the delay landing right
            // now, turned back into a radius. It runs out through the corners.
            if let burst, choreography == .radial, progress > 0.001, progress < 0.999 {
                let front = max((progress - window / 2) / span, 0)
                let radius = front * 0.7071 * Double(count - 1) * scale
                let box = CGRect(x: size.width / 2 - radius, y: size.height / 2 - radius,
                                 width: radius * 2, height: radius * 2)
                let ring = Path(ellipseIn: box)
                let tint = burst.swiftUIColor
                context.drawLayer { layer in
                    layer.addFilter(.blur(radius: 9))
                    layer.stroke(ring, with: .color(tint.opacity(0.55)), lineWidth: 16)
                }
                context.stroke(ring, with: .color(tint.opacity(0.9)), lineWidth: 1.5)
            }
        }
    }
}

/// A single hairline sweeping the card while verification runs. Mechanical:
/// constant speed, hard edges, no glow.
struct ScanSweep: View {
    @Environment(\.signalAccent) private var accent
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(accent)
                .frame(height: 1.5)
                .offset(y: geometry.size.height * phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 0.85).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// What sits in the hero slot before anything has been generated: the grid the
/// symbol will occupy, drawn as a faint lattice on the paper card.
struct EmptyCardPlaceholder: View {
    var body: some View {
        ZStack {
            Theme.elevated
            Canvas { context, size in
                let step = size.width / 21
                var path = Path()
                for index in 0...21 {
                    let position = CGFloat(index) * step
                    path.move(to: CGPoint(x: position, y: 0))
                    path.addLine(to: CGPoint(x: position, y: size.height))
                    path.move(to: CGPoint(x: 0, y: position))
                    path.addLine(to: CGPoint(x: size.width, y: position))
                }
                context.stroke(path, with: .color(.white.opacity(0.05)), lineWidth: 0.5)
            }
        }
    }
}
