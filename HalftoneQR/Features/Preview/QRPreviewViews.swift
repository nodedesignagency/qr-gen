import SwiftUI

/// The hero. A rendered symbol on its paper field, centred with room around it.
///
/// While a plan is animating it is drawn live at module resolution, which is
/// cheap enough to hold a steady frame rate on the densest symbol the app can
/// produce. Once it settles, the full-resolution halftone bitmap takes over and
/// the detail sharpens in rather than fading.
struct QRPreview: View {
    let plan: RenderPlan?
    var resolveProgress: Double = 1
    var choreography: Choreography = .structureFirst
    var isScanning: Bool = false

    @State private var rendered: CGImage?
    @State private var renderedPlanID: UUID?

    var body: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            symbol(side: side)
                .frame(width: side, height: side)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .aspectRatio(1, contentMode: .fit)
        .task(id: plan?.id) {
            guard let plan else { return }
            let image = await Task.detached(priority: .userInitiated) {
                RasterRenderer.image(for: plan, pixelSize: 1100).map(SendableImage.init)
            }.value
            guard !Task.isCancelled else { return }
            rendered = image?.image
            renderedPlanID = plan.id
        }
    }

    @ViewBuilder
    private func symbol(side: CGFloat) -> some View {
        ZStack {
            if let plan {
                if resolveProgress < 1 {
                    ModuleResolveCanvas(plan: plan, progress: resolveProgress,
                                        choreography: choreography)
                } else if let rendered, renderedPlanID == plan.id {
                    Image(decorative: rendered, scale: 1, orientation: .up)
                        .resizable()
                        .interpolation(.high)
                        .scaledToFit()
                } else {
                    // The bitmap is still rendering; the live canvas stands in so
                    // there is never an empty frame.
                    ModuleResolveCanvas(plan: plan, progress: 1, choreography: choreography)
                }
            } else {
                EmptyPreviewPlaceholder()
            }

            if isScanning {
                ScanSweep()
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: side * 0.055, style: .continuous))
    }
}

/// Module-resolution live drawing.
///
/// Cells are grouped into a handful of scale buckets and each bucket is filled as
/// a single path, so a 61-module symbol costs a few path fills per frame instead
/// of several thousand.
struct ModuleResolveCanvas: View {
    let plan: RenderPlan
    let progress: Double
    let choreography: Choreography

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
                    let bucket = min(Int(landed * Double(Self.buckets - 1)), Self.buckets - 1)
                    let blockSize = landed * scale
                    let cx = (plan.quietZone + Double(x) + 0.5) * scale
                    let cy = (plan.quietZone + Double(y) + 0.5) * scale
                    paths[bucket].addRect(CGRect(x: cx - blockSize / 2, y: cy - blockSize / 2,
                                                 width: blockSize, height: blockSize))
                }
            }

            let ink = plan.palette.ink.swiftUIColor
            for path in paths where !path.isEmpty {
                context.fill(path, with: .color(ink))
            }
        }
    }
}

/// A single hairline sweeping the symbol while verification runs. Mechanical:
/// constant speed, hard edges, no glow.
struct ScanSweep: View {
    @Environment(\.signalAccent) private var accent
    @State private var phase: CGFloat = 0

    var body: some View {
        GeometryReader { geometry in
            Rectangle()
                .fill(accent)
                .frame(height: 1)
                .offset(y: geometry.size.height * phase)
        }
        .allowsHitTesting(false)
        .onAppear {
            withAnimation(.linear(duration: 0.9).repeatForever(autoreverses: false)) {
                phase = 1
            }
        }
    }
}

/// What sits in the hero slot before anything has been generated: the grid the
/// symbol will occupy, drawn as a faint lattice.
struct EmptyPreviewPlaceholder: View {
    var body: some View {
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
            context.stroke(path, with: .color(.white.opacity(0.045)), lineWidth: 0.5)
        }
        .background(Theme.sunken)
    }
}
