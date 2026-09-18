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
/// as the slot rather than imitated. Everything above its lower lip is clipped
/// away, which is what makes the card look like it comes out of the hardware.
///
/// On a device without an island there is nothing to emerge from, so a small
/// black pill is drawn instead.
enum IslandMetrics {
    static let size = CGSize(width: 126, height: 37)
    static let topFromScreen: CGFloat = 11
    /// The card is clipped a little *above* the lip so it tucks behind the real
    /// island. The system draws the island over app content, so the overlap is
    /// hidden and there can be no sliver of background between the two.
    static let tuck: CGFloat = 6

    static func hasIsland(topSafeArea: CGFloat) -> Bool { topSafeArea >= 51 }

    static func top(topSafeArea: CGFloat) -> CGFloat {
        hasIsland(topSafeArea: topSafeArea) ? topFromScreen : max(topSafeArea - 8, 8)
    }

    static func slotBottom(topSafeArea: CGFloat) -> CGFloat {
        top(topSafeArea: topSafeArea) + size.height
    }
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

    /// Slow on purpose. The reference takes about this long, and the whole point
    /// is that it reads as a mechanism doing work.
    private let duration: Double = 2.6

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
        let emergeWidth = IslandMetrics.size.width

        // The card feeds out at the slot's width, then is released and grows.
        let extrude = segment(t, 0.02, 0.52)
        let release = segment(t, 0.52, 0.80)
        let develop = segment(t, 0.34, 1.0)

        let width = emergeWidth + (target.width - emergeWidth) * CGFloat(release)
        let extrudedCentre = slotBottom - emergeWidth / 2 + emergeWidth * CGFloat(extrude)
        let centreY = extrudedCentre + (target.midY - extrudedCentre) * CGFloat(release)
        let centreX = size.width / 2 + (target.midX - size.width / 2) * CGFloat(release)

        ZStack {
            if !IslandMetrics.hasIsland(topSafeArea: topSafeArea) {
                // Nothing to emerge from, so give it a slot of its own.
                RoundedRectangle(cornerRadius: IslandMetrics.size.height / 2, style: .continuous)
                    .fill(Color.black)
                    .frame(width: IslandMetrics.size.width, height: IslandMetrics.size.height)
                    .position(x: size.width / 2,
                              y: IslandMetrics.top(topSafeArea: topSafeArea) + IslandMetrics.size.height / 2)
            }

            if let plan {
                PrintedCard(plan: plan, choreography: choreography, progress: develop)
                    .frame(width: width, height: width)
                    .position(x: centreX, y: centreY)
                    // The shadow only arrives once the card is clear of the slot;
                    // while it is still in there it has nothing to cast onto.
                    .shadow(color: .black.opacity(0.24 * release),
                            radius: 24 * release, y: 12 * release)
                    .mask(alignment: .bottom) {
                        Rectangle().padding(.top, slotBottom - IslandMetrics.tuck)
                    }
            }
        }
    }
}

/// The card being printed: the real artwork, developing module by module.
///
/// This is the same plan the exporter writes, so what is watched printing is
/// byte-identical to the PNG that comes out the other end.
struct PrintedCard: View {
    let plan: RenderPlan
    let choreography: Choreography
    let progress: Double

    var body: some View {
        ModuleResolveCanvas(plan: plan, progress: progress, choreography: choreography)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
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
