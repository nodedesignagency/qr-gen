import SwiftUI
import UIKit

/// Where the generate sequence has got to.
enum GeneratePhase: Equatable {
    case idle
    /// Rendering and verifying. Nothing has come out of the slot yet.
    case working
    /// The card is being printed, driven by a single normalised clock.
    case printing

    var isRunning: Bool { self != .idle }
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
    /// Roughly the island's width. Only used to size the emerging card, where
    /// being a couple of points out is invisible.
    static let approximateWidth: CGFloat = 125

    static func hasIsland(topSafeArea: CGFloat) -> Bool { topSafeArea >= 51 }

    /// The lower lip of the slot, in screen coordinates.
    static func slotBottom(topSafeArea: CGFloat) -> CGFloat {
        hasIsland(topSafeArea: topSafeArea)
            ? topSafeArea - lipToSafeArea
            : max(topSafeArea - 10, 26)
    }

    /// The card is clipped a little *above* the lip so it tucks behind the real
    /// island. The system draws the island over app content, so the overlap is
    /// hidden and there can be no sliver of background between the two. This also
    /// absorbs any error in the derived lip.
    static let tuck: CGFloat = 8
}

/// Smoothstep, clamped.
private func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

/// A sub-range of the master clock, remapped to 0...1 and smoothed.
private func segment(_ t: Double, _ start: Double, _ end: Double) -> Double {
    smoothstep((t - start) / (end - start))
}

/// The generate animation.
///
/// Three overlapping windows on one clock, in the order a real instant camera
/// does them:
///
/// 1. **Extrude.** The card feeds straight down out of the slot at the island's
///    own width, at a constant width, slowly. It stays touching the slot the
///    whole way — it is pushed out, not thrown.
/// 2. **Release.** Once it is clear it detaches, grows to full size and settles
///    into the frame the page keeps for it.
/// 3. **Develop.** The image comes up late and finishes after the card lands,
///    the way a print does.
struct PrintSequenceOverlay: View {
    let phase: GeneratePhase
    let plan: RenderPlan?
    let choreography: Choreography
    let accent: Color
    /// Where the card is going, in global coordinates.
    let destination: CGRect
    let start: Date

    /// Long enough to read as a mechanism, with nothing dead in it.
    private let duration: Double = 2.2

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            TimelineView(.animation) { timeline in
                content(t: clock(now: timeline.date),
                        size: geometry.size,
                        topSafeArea: topInset)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private func clock(now: Date) -> Double {
        guard phase == .printing else { return 0 }
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    @ViewBuilder
    private func content(t: Double, size: CGSize, topSafeArea: CGFloat) -> some View {
        let target = destination == .zero
            ? CGRect(x: (size.width - 353) / 2, y: size.height * 0.30, width: 353, height: 353)
            : destination

        let slotBottom = IslandMetrics.slotBottom(topSafeArea: topSafeArea)
        let emergeWidth = IslandMetrics.approximateWidth

        let extrude = segment(t, 0.04, 0.60)
        let release = segment(t, 0.60, 0.88)
        // The image is laid down *at the slot*, in step with the feed, so the
        // paper comes out already printed. Developing afterwards left a second of
        // blank card inching out, which was the deadest part of the sequence.
        // The small lead means a row is finished just before it appears.
        let develop = segment(t, 0.02, 0.58)

        // It clears the slot, flares, and lands with a little overshoot — the
        // moment the print commits.
        let flash = pulse(t, centre: 0.63, width: 0.07)
        let settle = pulse(t, centre: 0.90, width: 0.13)

        // Rollers are never perfectly smooth. A little judder while it feeds is
        // the difference between a mechanism and a sliding rectangle.
        let feeding = pulse(t, centre: 0.30, width: 0.32)
        let judder = 0.5 * sin(t * 38) * feeding

        let width = (emergeWidth + (target.width - emergeWidth) * CGFloat(release))
            * (1 + 0.045 * CGFloat(settle))
        let extrudedCentre = slotBottom - emergeWidth / 2 + emergeWidth * CGFloat(extrude)
        let centreY = extrudedCentre + (target.midY - extrudedCentre) * CGFloat(release)
        let centreX = size.width / 2 + (target.midX - size.width / 2) * CGFloat(release)

        ZStack {
            if !IslandMetrics.hasIsland(topSafeArea: topSafeArea) {
                // Nothing to emerge from, so give it a slot of its own.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black)
                    .frame(width: emergeWidth, height: 36)
                    .position(x: size.width / 2, y: slotBottom - 18)
            }

            // The slot lights while it is feeding, so the island reads as the
            // machine doing the work without ever changing shape.
            if extrude > 0.001 && extrude < 0.999 {
                Capsule()
                    .fill(accent)
                    .frame(width: emergeWidth * 0.82, height: 3)
                    .blur(radius: 3)
                    .opacity(0.9 * feeding)
                    .position(x: size.width / 2, y: slotBottom - 1)
                    .allowsHitTesting(false)
            }

            if let plan {
                PrintedCard(plan: plan,
                            choreography: Self.printChoreography,
                            progress: develop,
                            flash: flash,
                            accent: accent)
                    .frame(width: width, height: width)
                    .rotationEffect(.degrees(1.6 * settle + judder))
                    .position(x: centreX, y: centreY)
                    // The shadow only arrives once the card is clear of the slot;
                    // while it is still in there it has nothing to cast onto.
                    .shadow(color: .black.opacity(0.26 * release),
                            radius: 26 * release, y: 13 * release)
                    .shadow(color: accent.opacity(0.5 * flash), radius: 44 * flash)
                    .mask(alignment: .bottom) {
                        Rectangle().padding(.top, slotBottom - IslandMetrics.tuck)
                    }
            }
        }
    }

    /// The print always uses the feed order, whatever the user has picked for the
    /// preview: bottom-up, so each row lands exactly as it clears the slot.
    static let printChoreography: Choreography = .feed
}

/// A 0...1 bump centred on `centre`, `width` wide, smoothed at both ends.
private func pulse(_ t: Double, centre: Double, width: Double) -> Double {
    let distance = abs(t - centre) / width
    return smoothstep(1 - min(distance, 1))
}

/// The card being printed: the real artwork, developing module by module.
///
/// This is the same plan the exporter writes, so what is watched printing is
/// byte-identical to the PNG that comes out the other end.
///
/// Two things carry the middle of the sequence. A wash sweeps down the card
/// ahead of the modules, so the image is visibly being laid down rather than
/// just appearing — the band tracks the same scanline order the modules resolve
/// in, so the light is always exactly where the work is. And the card flares
/// once, at the instant it clears the slot and commits.
struct PrintedCard: View {
    let plan: RenderPlan
    let choreography: Choreography
    let progress: Double
    var flash: Double = 0
    var accent: Color = .white

    var body: some View {
        ZStack {
            ModuleResolveCanvas(plan: plan, progress: progress, choreography: choreography)

            if progress > 0.001 && progress < 0.999 {
                LinearGradient(stops: washStops, startPoint: .bottom, endPoint: .top)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }

            if flash > 0.001 {
                Color.white
                    // Enough to read as a flare, not enough to blank the card —
                    // at 0.75 it wiped the image out for a beat.
                    .opacity(0.42 * flash)
                    .blendMode(.plusLighter)
                    .allowsHitTesting(false)
            }
        }
        .compositingGroup()
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    /// A bright band centred on the resolving front.
    ///
    /// `ModuleResolveCanvas` staggers each module by its scanline delay across
    /// `1 - landingWindow`, so the front sits half a window behind the clock.
    /// Deriving it rather than eyeballing keeps the light on the work even if the
    /// choreography's timings are retuned.
    private var washStops: [Gradient.Stop] {
        let window = choreography.landingWindow
        let centre = (progress - window / 2) / (1 - window)
        let lead = min(max(centre - 0.13, 0), 1)
        let peak = min(max(centre - 0.01, 0), 1)
        let tail = min(max(centre + 0.08, 0), 1)
        return [
            Gradient.Stop(color: .clear, location: 0),
            Gradient.Stop(color: .clear, location: lead),
            Gradient.Stop(color: accent.opacity(0.35), location: (lead + peak) / 2),
            Gradient.Stop(color: Color.white.opacity(0.9), location: peak),
            Gradient.Stop(color: .clear, location: tail),
            Gradient.Stop(color: .clear, location: 1),
        ]
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
