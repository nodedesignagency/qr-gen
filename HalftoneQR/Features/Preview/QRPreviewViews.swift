import SwiftUI

/// The hero: the symbol on its paper card, big and centred with room around it.
///
/// The symbol is drawn live from the real plan geometry — the same cells the
/// exporter writes — whether it is resolving or at rest. There is no bitmap to
/// swap in at the end: the drawing that animates is the drawing that stays, so
/// nothing about the symbol can change when an animation completes. The
/// exports render their own bitmaps from the same geometry, in the same colour
/// space.
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
    }

    @ViewBuilder
    private func card(side: CGFloat) -> some View {
        ZStack {
            if let plan {
                // The paper fills the card to its own corners. The plan's paper
                // is rounded in module units for the exports, and inside a 24pt
                // clip that left the corners open.
                plan.palette.paper.swiftUIColor

                if let startedAt {
                    TimelineView(.animation) { timeline in
                        let elapsed = timeline.date.timeIntervalSince(startedAt)
                        PlanResolveCanvas(plan: plan, progress: min(max(elapsed / duration, 0), 1),
                                          choreography: choreography, drawsPaper: false)
                    }
                } else {
                    PlanResolveCanvas(plan: plan, progress: 1, choreography: choreography, drawsPaper: false)
                }
            } else {
                EmptyCardPlaceholder()
            }

            if isScanning { ScanSweep() }
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius ?? side * 0.085, style: .continuous))
    }
}

/// Live drawing of a plan part-way through its resolve, at the real geometry.
///
/// Draws `plan.revealed(by:at:)` — the same primitives the exporter writes, at
/// their real shapes and sizes — so the last frame *is* the still. Each colour
/// group is one path fill, so a dense symbol costs a handful of fills per frame.
struct PlanResolveCanvas: View {
    let plan: RenderPlan
    let progress: Double
    let choreography: Choreography
    /// Whether to lay the plan's paper down here. The card draws its own paper
    /// underneath, to its own corners, and has this draw the cells alone.
    var drawsPaper: Bool = true

    var body: some View {
        Canvas(opaque: false, rendersAsynchronously: false) { context, size in
            let side = size.width
            let scale = side / plan.canvasUnits
            let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: scale, tx: 0, ty: 0)

            // The bang: light at the centre, gone as the cloud spreads.
            if choreography == .bigBang, progress > 0.001, progress < 0.30 {
                let u = progress / 0.30
                let radius = side * (0.08 + 0.55 * u)
                let centre = CGPoint(x: size.width / 2, y: size.height / 2)
                let light = plan.palette.ink.swiftUIColor
                context.fill(Path(ellipseIn: CGRect(x: centre.x - radius, y: centre.y - radius,
                                                    width: radius * 2, height: radius * 2)),
                             with: .radialGradient(Gradient(colors: [light.opacity(0.5 * (1 - u)),
                                                                     light.opacity(0)]),
                                                   center: centre, startRadius: 0, endRadius: radius))
            }

            let revealed = plan.revealed(by: choreography, at: progress)
            for (index, group) in PlanFlattener.flatten(revealed).enumerated() {
                // The paper field is always the first group.
                if index == 0 && !drawsPaper { continue }
                let path = Path(PathGeometry.cgPath(for: group.primitives, transform: transform))
                // Even-odd lets the finder rings carve their own holes, and is
                // identical to non-zero for the grid shapes, which never overlap.
                context.fill(path, with: .color(group.colour.swiftUIColor),
                             style: FillStyle(eoFill: true))
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
