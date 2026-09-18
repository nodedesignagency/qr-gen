import SwiftUI
import UIKit

/// Where the generate sequence has got to.
enum GeneratePhase: Equatable {
    case idle
    /// Rendering and verifying. A small drop hangs from the island while it waits.
    case working
    /// The drop is letting go and spreading into the card, on one clock.
    case printing
    /// The card is being drawn back into the island, because its inputs changed.
    case retracting

    var isRunning: Bool { self != .idle }

    /// True while the overlay owns the card and it may cross the page's title.
    var isMovingCard: Bool { self == .printing || self == .retracting }
}

/// Geometry for the Dynamic Island.
///
/// The island is never redrawn or resized here. It belongs to the system, it
/// renders above app content, and it is already the right shape — so it is used
/// as the slot rather than imitated.
///
/// Its position is *derived*, not hardcoded. Hardcoded points are only ever
/// right for the handsets they were measured on, and a device released after
/// this code was written would land the card in the wrong place. On every island
/// device the top safe area begins a small fixed margin below the island's lower
/// edge, so that inset gives the lip on any hardware, including hardware that
/// does not exist yet.
enum IslandMetrics {
    /// Gap between the island's lower edge and where the safe area starts.
    private static let lipToSafeArea: CGFloat = 11.5
    /// Roughly the island's width. Only used for the stand-in slot on devices
    /// without an island, where being a couple of points out is invisible.
    static let approximateWidth: CGFloat = 125

    static func hasIsland(topSafeArea: CGFloat) -> Bool { topSafeArea >= 51 }

    /// The lower lip of the slot, in screen coordinates.
    static func slotBottom(topSafeArea: CGFloat) -> CGFloat {
        hasIsland(topSafeArea: topSafeArea)
            ? topSafeArea - lipToSafeArea
            : max(topSafeArea - 10, 26)
    }

    /// The drop's neck springs from a line this far *above* the lip. The system
    /// draws the island over app content, so the join is hidden behind the
    /// island's own edge and any error in the derived lip cannot show as a gap
    /// between the two.
    static let tuck: CGFloat = 2
}

// MARK: - Easing

/// Smoothstep, clamped.
private func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

/// A sub-range of the master clock, remapped to 0...1 and smoothed.
private func segment(_ t: Double, _ start: Double, _ end: Double) -> Double {
    smoothstep((t - start) / (end - start))
}

private func clamp01(_ x: Double) -> Double { min(max(x, 0), 1) }

private func lerp(_ a: Double, _ b: Double, _ t: Double) -> Double { a + (b - a) * t }

private func easeOut(_ x: Double, power: Double) -> Double {
    1 - pow(1 - clamp01(x), power)
}

/// The step response of an underdamped spring, normalised so it has settled by
/// `x = 1`. `overshoot` is how far past the target the first swing goes.
///
/// Written out rather than taken from `Animation.spring` because the sequence
/// runs on one scrubbed clock: it has to be a function of time, not a state
/// change, so it can be played backwards.
private func spring(_ x: Double, overshoot: Double) -> Double {
    let x = clamp01(x)
    guard x < 1 else { return 1 }
    let ln = log(overshoot)
    let zeta = -ln / sqrt(Double.pi * Double.pi + ln * ln)
    let natural = 5.5 / zeta
    let damped = natural * sqrt(1 - zeta * zeta)
    let decay = exp(-zeta * natural * x)
    let response = 1 - decay * (cos(damped * x) + zeta / sqrt(1 - zeta * zeta) * sin(damped * x))
    // The tail is blended out so it ends exactly on target, not 0.4% short.
    return response + (1 - response) * smoothstep((x - 0.82) / 0.18)
}

// MARK: - Timeline

/// The generate animation: a drop the island lets go of.
///
/// One normalised clock, `t` in 0...1 over `duration`. Everything on screen is a
/// pure function of `t`, which is what makes the sequence scrubbable — and lets
/// it run backwards to withdraw the card when its inputs change.
///
/// Three overlapping windows:
///
/// 1. **Swell.** The island's lower edge bulges, and the bulge hangs into a
///    drop. The join is a pair of fillets tangent to both the edge and the
///    drop — the surface-tension shape — and the fillet radius is what sets
///    how far the shoulders spread.
/// 2. **Stretch and let go.** The drop pulls into a pill and the fillets shrink
///    until the neck is thinner than `minimumNeck` and snaps. What the island
///    keeps springs back. The colour runs from the island's black to paper down
///    the drop as it goes, so it leaves as the card, not as a piece of island.
/// 3. **Spread.** The freed drop falls and spreads into the card: its width
///    first, then its lower edge, each on its own spring. That is what makes it
///    read as liquid settling rather than a rectangle being scaled. The symbol
///    develops as the card lands.
///
/// Tuned in `Tools/liquid_proto.py`, which draws the same geometry frame by
/// frame; the constants here are the ones that were read off it.
enum LiquidTimeline {

    static let duration: TimeInterval = 2.0
    /// The withdraw is quicker: the modules leave, then the card is pulled back.
    static let retractDuration: TimeInterval = 0.9

    // Beats, as fractions of `duration`.
    static let swellEnd = 0.10
    static let stretchEnd = 0.18
    /// When the neck snaps. Fixed by the geometry, so the haptics can rely on it.
    static let breakAt = 0.137
    static let landAt = 0.55
    /// When the real card view takes over from the drawn blob.
    static let handoverAt = 0.38
    static let handoverWidth = 0.05
    static let developAt = 0.42

    static let cardRadius: Double = 24
    /// The neck snaps once it is thinner than this, rather than thinning to a
    /// hair — a hair reads as a rendering artefact, not as a drop letting go.
    static let minimumNeck: Double = 5

    /// One instant of the sequence, in screen coordinates.
    struct Frame {
        /// The drop, then the card. Its corner radius is `width / 2` for as long
        /// as it is a drop.
        var rect: CGRect
        var cornerRadius: Double
        /// Fillet radius of the neck joining it to the island; 0 once it has gone.
        var neck: Double
        /// How much of the island's black is left in the drop, at its top and
        /// bottom edges. 1 is island, 0 is paper.
        var darkTop: Double
        var darkBottom: Double
        /// Radius of the bump the island keeps after the neck snaps.
        var residual: Double
        /// Crossfade from the drawn blob to the real card view.
        var cardOpacity: Double
        /// Module resolve progress.
        var develop: Double
        var shadow: Double
    }

    /// - Parameters:
    ///   - line: the y the neck springs from, just above the island's lip.
    ///   - centreX: the island's centre.
    ///   - target: where the card lands.
    ///   - breath: a small vertical offset for the hanging drop while the app is
    ///     still working. It is faded out as the swell begins, so there is no
    ///     seam between waiting and going.
    static func frame(at t: Double, line: Double, centreX: Double,
                      target: CGRect, breath: Double = 0) -> Frame {
        let swell = segment(t, 0, swellEnd)
        let stretch = segment(t, swellEnd - 0.02, stretchEnd)
        let breathing = breath * (1 - segment(t, 0, 0.06))

        // The drop, hand-tuned: it starts as a bulge mostly behind the island,
        // hangs, then stretches from the bottom.
        let dropWidth = lerp(18, 32, swell) + 4 * stretch
        let dropTop = line + lerp(-12, 0, swell) + 26 * stretch + breathing
        let dropBottom = line + lerp(6, 32, swell) + 46 * stretch + breathing

        // The fall. Each edge on its own curve, so the card spreads rather than
        // scales: width first and fast, the lower edge last and springiest.
        let fall = clamp01((t - stretchEnd) / (landAt - stretchEnd))
        let widthCurve = spring(fall / 0.62, overshoot: 0.02)
        let topCurve = spring(fall / 0.86, overshoot: 0.04)
        let bottomCurve = spring(clamp01((fall - 0.08) / 0.92), overshoot: 0.05)

        let width = lerp(dropWidth, target.width, widthCurve)
        let top = lerp(dropTop, target.minY, topCurve)
        let bottom = lerp(dropBottom, target.maxY, bottomCurve)
        let midX = lerp(centreX, target.midX, easeOut(fall / 0.6, power: 3))
        let rect = CGRect(x: midX - width / 2, y: top, width: width, height: bottom - top)

        // Rounder while in flight, settling to the card's own radius as it lands.
        let inFlightRadius = cardRadius + 26 * (1 - easeOut(fall / 0.9, power: 2))
        let cornerRadius = min(width / 2, (bottom - top) / 2, inFlightRadius)

        // Broad shoulders while it hangs, thinning as it stretches, then gone.
        let neck = lerp(14, 16, segment(t, 0, swellEnd)) * (1 - segment(t, swellEnd, stretchEnd))

        // The bottom lightens first and the top follows, so the black drains
        // out of the drop downwards, away from the island.
        let darkBottom = 1 - segment(t, 0.05, 0.17)
        let darkTop = 1 - segment(t, 0.10, 0.26)

        // What the island keeps: a bump that springs back with one bounce.
        var residual = 0.0
        let sinceBreak = (t - breakAt) * duration
        if sinceBreak > 0 {
            residual = 6 * exp(-7 * sinceBreak) * max(cos(11 * sinceBreak), 0)
        }

        return Frame(rect: rect,
                     cornerRadius: cornerRadius,
                     neck: neck,
                     darkTop: darkTop,
                     darkBottom: darkBottom,
                     residual: residual,
                     cardOpacity: segment(t, handoverAt, handoverAt + handoverWidth),
                     develop: clamp01((t - developAt) / (1 - developAt)),
                     shadow: segment(t, breakAt, 0.40))
    }

    /// The withdraw: seconds since it began, mapped onto the clock backwards.
    /// The modules leave quickly, then the card rises at its own pace.
    static func retractTime(elapsed: TimeInterval) -> Double {
        let undevelop = 0.28
        let rise = retractDuration - undevelop
        if elapsed < undevelop {
            return lerp(1, developAt, clamp01(elapsed / undevelop))
        }
        return lerp(developAt, 0, clamp01((elapsed - undevelop) / rise))
    }

    // MARK: Geometry

    /// The drop joined to the island's edge by two fillets, as one closed path.
    ///
    /// The drop is a capsule: circles of `radius` centred at `top` and `bottom`.
    /// Where the fillets meet it depends on how far it hangs below `line`:
    ///
    /// - **A.** Hanging (`top - line >= fillet`): tangent to the top circle,
    ///   above its equator.
    /// - **B.** Emerging pill: tangent to the straight sides, at `line + fillet`.
    /// - **C.** Emerging circle: only the underside shows, so tangent to the
    ///   bottom circle below its equator.
    ///
    /// The three agree exactly at their boundaries, so the shape never jumps as
    /// the drop moves between them.
    ///
    /// Returns `nil` once the fillets cannot reach, or the neck has thinned past
    /// `minimumNeck` — that is the snap.
    static func attachedPath(centreX cx: Double, line: Double,
                             top ya: Double, bottom yb: Double,
                             radius r: Double, fillet k: Double) -> Path? {
        guard k > 0.05 else { return nil }
        let d = ya - line
        var path = Path()

        if d >= k {
            let reach = (r + k) * (r + k) - (d - k) * (d - k)
            guard reach > 0.01, d <= r + 2 * k else { return nil }
            let fx = sqrt(reach)
            guard 2 * (fx - k) >= minimumNeck else { return nil }

            let left = CGPoint(x: cx - fx, y: line + k)
            let right = CGPoint(x: cx + fx, y: line + k)
            let centre = CGPoint(x: cx, y: ya)
            let share = k / (r + k)
            let tangentLeft = CGPoint(x: left.x + (centre.x - left.x) * share,
                                      y: left.y + (centre.y - left.y) * share)
            let tangentRight = CGPoint(x: right.x + (centre.x - right.x) * share,
                                       y: right.y + (centre.y - right.y) * share)

            path.move(to: CGPoint(x: left.x, y: line))
            addArc(&path, centre: left, radius: k, from: -.pi / 2, to: atan2(d - k, fx))
            addArc(&path, centre: centre, radius: r,
                   from: atan2(tangentLeft.y - centre.y, tangentLeft.x - centre.x), to: -.pi)
            path.addLine(to: CGPoint(x: cx - r, y: yb))
            addArc(&path, centre: CGPoint(x: cx, y: yb), radius: r, from: .pi, to: 0)
            path.addLine(to: CGPoint(x: cx + r, y: ya))
            addArc(&path, centre: centre, radius: r,
                   from: 0, to: atan2(tangentRight.y - centre.y, tangentRight.x - centre.x))
            var back = atan2(d - k, -fx)
            if back < 0 { back += 2 * .pi }
            addArc(&path, centre: right, radius: k, from: back, to: 3 * .pi / 2)
        } else if line + k <= yb {
            let left = CGPoint(x: cx - r - k, y: line + k)
            let right = CGPoint(x: cx + r + k, y: line + k)

            path.move(to: CGPoint(x: left.x, y: line))
            addArc(&path, centre: left, radius: k, from: -.pi / 2, to: 0)
            path.addLine(to: CGPoint(x: cx - r, y: yb))
            addArc(&path, centre: CGPoint(x: cx, y: yb), radius: r, from: .pi, to: 0)
            path.addLine(to: CGPoint(x: cx + r, y: line + k))
            addArc(&path, centre: right, radius: k, from: .pi, to: 3 * .pi / 2)
        } else {
            let db = yb - line
            let reach = (r + k) * (r + k) - (k - db) * (k - db)
            guard reach > 0.01 else { return nil }
            let fx = sqrt(reach)

            let left = CGPoint(x: cx - fx, y: line + k)
            let right = CGPoint(x: cx + fx, y: line + k)
            let centre = CGPoint(x: cx, y: yb)
            let share = k / (r + k)
            let tangentLeft = CGPoint(x: left.x + (centre.x - left.x) * share,
                                      y: left.y + (centre.y - left.y) * share)
            let tangentRight = CGPoint(x: right.x + (centre.x - right.x) * share,
                                       y: right.y + (centre.y - right.y) * share)

            path.move(to: CGPoint(x: left.x, y: line))
            addArc(&path, centre: left, radius: k, from: -.pi / 2, to: atan2(db - k, fx))
            addArc(&path, centre: centre, radius: r,
                   from: atan2(tangentLeft.y - centre.y, tangentLeft.x - centre.x),
                   to: atan2(tangentRight.y - centre.y, tangentRight.x - centre.x))
            var back = atan2(db - k, -fx)
            if back < 0 { back += 2 * .pi }
            addArc(&path, centre: right, radius: k, from: back, to: 3 * .pi / 2)
        }

        path.closeSubpath()
        return path
    }

    /// An arc from one angle to another, in whichever direction gets there.
    ///
    /// Angles are in SwiftUI's y-down space, so 0 points right and π/2 points
    /// down. `clockwise: false` sweeps through *increasing* angles — the
    /// direction a progress ring is drawn in — so the flag is derived from the
    /// sign of the sweep rather than guessed.
    private static func addArc(_ path: inout Path, centre: CGPoint, radius: Double,
                               from start: Double, to end: Double) {
        path.addArc(center: centre, radius: radius,
                    startAngle: .radians(start), endAngle: .radians(end),
                    clockwise: end < start)
    }

    // MARK: Drawing

    /// Draws everything except the real card: the stand-in slot, the drop with
    /// its neck, the freed blob until the card takes over, and the bump the
    /// island keeps.
    static func draw(_ frame: Frame, in context: inout GraphicsContext,
                     line: Double, centreX: Double, paper: RGB, ownSlot: CGRect?) {
        let island = RGB(red: 0, green: 0, blue: 0)
        let islandColour = island.swiftUIColor

        if let slot = ownSlot {
            context.fill(Path(roundedRect: slot, cornerRadius: slot.height / 2, style: .continuous),
                         with: .color(islandColour))
        }

        let rect = frame.rect
        let radius = rect.width / 2
        let topColour = paper.mixed(with: island, amount: frame.darkTop).swiftUIColor
        let bottomColour = paper.mixed(with: island, amount: frame.darkBottom).swiftUIColor

        // The neck only exists while the drop is still a capsule.
        let isCapsule = abs(frame.cornerRadius - radius) < 0.01
        let attached = isCapsule && frame.neck > 0
            ? attachedPath(centreX: centreX, line: line,
                           top: rect.minY + radius, bottom: rect.maxY - radius,
                           radius: radius, fillet: frame.neck)
            : nil

        context.drawLayer { layer in
            if frame.shadow > 0.01 && frame.cardOpacity < 1 {
                layer.addFilter(.shadow(color: .black.opacity(0.18 * frame.shadow), radius: 18, y: 9))
            }
            if let attached {
                // One gradient down the whole thing: island black at the line,
                // the drop's own colours from its top edge to its bottom.
                let span = max(rect.maxY - line, 1)
                let stops = [
                    Gradient.Stop(color: islandColour, location: 0),
                    Gradient.Stop(color: topColour, location: clamp01((rect.minY - line) / span)),
                    Gradient.Stop(color: bottomColour, location: 1),
                ]
                layer.fill(attached,
                           with: .linearGradient(Gradient(stops: stops),
                                                 startPoint: CGPoint(x: centreX, y: line),
                                                 endPoint: CGPoint(x: centreX, y: rect.maxY)))
            } else if frame.cardOpacity < 1 {
                // Circular corners here, to match the arcs the neck was built
                // from; the card's continuous corners arrive under the crossfade.
                let blob = Path(roundedRect: rect, cornerRadius: frame.cornerRadius, style: .circular)
                layer.fill(blob,
                           with: .linearGradient(Gradient(colors: [topColour, bottomColour]),
                                                 startPoint: CGPoint(x: rect.midX, y: rect.minY),
                                                 endPoint: CGPoint(x: rect.midX, y: rect.maxY)))
            }
        }

        if attached == nil, frame.residual > 0.2 {
            let bump = frame.residual
            if let path = attachedPath(centreX: centreX, line: line,
                                       top: line + bump * 0.35, bottom: line + bump * 0.35,
                                       radius: bump, fillet: bump * 1.4) {
                context.fill(path, with: .color(islandColour))
            }
        }
    }
}

// MARK: - Overlay

/// The generate animation, drawn over the page.
///
/// The island is the slot. This never draws the island itself — the system
/// renders it above app content, and it is already the right shape. The drop's
/// neck springs from a line just behind its lower edge, so the join is hidden
/// under the real thing. On a device without an island, a black pill stands in.
struct PrintSequenceOverlay: View {
    let phase: GeneratePhase
    let plan: RenderPlan?
    let choreography: Choreography
    /// Where the card is going, in global coordinates.
    let destination: CGRect
    let start: Date

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            TimelineView(.animation) { timeline in
                content(now: timeline.date, size: geometry.size, topSafeArea: topInset)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func clock(now: Date) -> Double {
        let elapsed = now.timeIntervalSince(start)
        switch phase {
        case .idle, .working:
            return 0
        case .printing:
            return clamp01(elapsed / LiquidTimeline.duration)
        case .retracting:
            return LiquidTimeline.retractTime(elapsed: elapsed)
        }
    }

    @ViewBuilder
    private func content(now: Date, size: CGSize, topSafeArea: CGFloat) -> some View {
        let target = destination == .zero
            ? CGRect(x: (size.width - 353) / 2, y: size.height * 0.30, width: 353, height: 353)
            : destination

        let slotBottom = IslandMetrics.slotBottom(topSafeArea: topSafeArea)
        let line = slotBottom - IslandMetrics.tuck
        let centreX = size.width / 2
        let t = clock(now: now)

        // A slow breath while it waits, taken from the wall clock so its phase
        // is continuous into the moment the drop starts to swell.
        let breath = 1.2 * sin(now.timeIntervalSinceReferenceDate * 2 * .pi * 0.6)
        let frame = LiquidTimeline.frame(at: t, line: line, centreX: centreX,
                                         target: target, breath: breath)

        let ownSlot: CGRect? = IslandMetrics.hasIsland(topSafeArea: topSafeArea)
            ? nil
            : CGRect(x: centreX - IslandMetrics.approximateWidth / 2, y: slotBottom - 36,
                     width: IslandMetrics.approximateWidth, height: 36)
        let paper = plan?.palette.paper ?? .paper

        ZStack {
            Canvas { context, _ in
                LiquidTimeline.draw(frame, in: &context, line: line, centreX: centreX,
                                    paper: paper, ownSlot: ownSlot)
            }

            if frame.cardOpacity > 0, let plan {
                PrintedCard(plan: plan, choreography: choreography,
                            progress: frame.develop, cornerRadius: frame.cornerRadius)
                    .frame(width: frame.rect.width, height: frame.rect.height)
                    .position(x: frame.rect.midX, y: frame.rect.midY)
                    .shadow(color: .black.opacity(0.18 * frame.shadow), radius: 18, y: 9)
                    .opacity(frame.cardOpacity)
            }
        }
    }
}

/// The card: the real artwork, developing module by module on its paper.
///
/// This is the same plan the exporter writes, so what is watched developing is
/// byte-identical to the PNG that comes out the other end. The paper is laid
/// down here as well as by the canvas, so the card's corners are its own and
/// not the plan's — the plan's radius is in module units and varies with the
/// symbol's version.
struct PrintedCard: View {
    let plan: RenderPlan
    let choreography: Choreography
    let progress: Double
    var cornerRadius: Double = LiquidTimeline.cardRadius

    var body: some View {
        ZStack {
            plan.palette.paper.swiftUIColor
            ModuleResolveCanvas(plan: plan, progress: progress, choreography: choreography)
        }
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
    }
}

/// Short, purposeful haptics for the machine.
enum Haptics {
    static func impact(_ style: UIImpactFeedbackGenerator.FeedbackStyle, intensity: CGFloat = 1) {
        let generator = UIImpactFeedbackGenerator(style: style)
        generator.prepare()
        generator.impactOccurred(intensity: intensity)
    }

    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func warning() {
        UINotificationFeedbackGenerator().notificationOccurred(.warning)
    }
}

/// The frame the page keeps for the printed card, reported up so the overlay can
/// land on it exactly.
struct CardSlotKey: PreferenceKey {
    static var defaultValue: CGRect { .zero }
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) {
        let next = nextValue()
        if next != .zero { value = next }
    }
}

extension View {
    /// Publishes this view's global frame as the destination for the print.
    func cardSlot() -> some View {
        background {
            GeometryReader { geometry in
                Color.clear.preference(key: CardSlotKey.self,
                                       value: geometry.frame(in: .global))
            }
        }
    }
}
