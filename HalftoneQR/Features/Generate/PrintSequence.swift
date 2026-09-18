import SwiftUI
import UIKit

/// Where the generate sequence has got to.
///
/// Only two live states. The first attempt at this had six, each handing off to
/// the next with its own spring, and the springs fought: the offset, the scale
/// and the mask all settled at different rates, so it snapped instead of
/// printing. One continuous timeline is smooth by construction.
enum GeneratePhase: Equatable {
    case idle
    /// Rendering and verifying. The slot holds a small working state.
    case working
    /// The card is being printed, driven by a single normalised clock.
    case printing

    var isRunning: Bool { self != .idle }
}

/// Geometry for the Dynamic Island.
///
/// An app cannot animate the real island — it belongs to the system, and
/// ActivityKit only ever hands it content, never frame-by-frame control. So this
/// draws its own black pill in the same place. The real island is opaque black,
/// so a black shape growing out from behind it reads as one object.
///
/// The open size is deliberately close to the closed one. Apple's own expansions
/// grow the pill by a few points and let the *content* do the work; going much
/// bigger stops reading as the island and starts reading as a black box.
enum IslandMetrics {
    static let closedSize = CGSize(width: 126, height: 37)
    static let openSize = CGSize(width: 168, height: 46)
    static let topFromScreen: CGFloat = 11

    /// Island devices report a noticeably deeper top inset than notched ones.
    static func hasIsland(topSafeArea: CGFloat) -> Bool { topSafeArea >= 51 }

    static func top(topSafeArea: CGFloat) -> CGFloat {
        hasIsland(topSafeArea: topSafeArea) ? topFromScreen : max(topSafeArea - 8, 8)
    }
}

/// Smoothstep, clamped. Every motion below is built from these so nothing
/// overshoots into anything else.
private func smoothstep(_ t: Double) -> Double {
    let x = min(max(t, 0), 1)
    return x * x * (3 - 2 * x)
}

/// A sub-range of the master clock, remapped to 0...1 and smoothed.
private func segment(_ t: Double, _ start: Double, _ end: Double) -> Double {
    smoothstep((t - start) / (end - start))
}

/// The generate animation: the slot opens, a card slides out of it, develops on
/// the way down, and settles into the frame the page already has waiting.
struct PrintSequenceOverlay: View {
    let phase: GeneratePhase
    let plan: RenderPlan?
    let choreography: Choreography
    let accent: Color
    /// Where the card is going, in global coordinates — the slot the page keeps
    /// for it, so the overlay can hand over without anything jumping.
    let destination: CGRect
    let start: Date

    /// Long enough to read as a mechanism, short enough not to be in the way.
    private let duration: Double = 1.55
    private let emergingWidth: CGFloat = 148

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            TimelineView(.animation) { timeline in
                let t = clock(now: timeline.date)
                content(t: t, size: geometry.size, topSafeArea: topInset)
            }
        }
        .ignoresSafeArea()
    }

    private func clock(now: Date) -> Double {
        guard phase == .printing else { return 0 }
        return min(max(now.timeIntervalSince(start) / duration, 0), 1)
    }

    @ViewBuilder
    private func content(t: Double, size: CGSize, topSafeArea: CGFloat) -> some View {
        // If the page has not reported its slot yet, aim for a sensible centre
        // rather than flying the card to the origin.
        let target = destination == .zero
            ? CGRect(x: (size.width - 353) / 2, y: size.height * 0.26, width: 353, height: 353)
            : destination
        let open = phase == .printing ? segment(t, 0, 0.22) : 0
        let travel = segment(t, 0.08, 0.60)
        let develop = segment(t, 0.26, 0.92)
        let islandTop = IslandMetrics.top(topSafeArea: topSafeArea)
        let islandHeight = lerp(IslandMetrics.closedSize.height, IslandMetrics.openSize.height, open)
        let slotBottom = islandTop + islandHeight

        // The card leaves the slot small and arrives at exactly the frame the
        // page is holding for it.
        let width = lerp(emergingWidth, target.width, travel)
        let centreX = lerp(size.width / 2, target.midX, travel)
        let centreY = lerp(slotBottom + emergingWidth / 2 - 14, target.midY, travel)

        ZStack {
            Color.black
                .opacity(0.30 * segment(t, 0, 0.25) * (1 - segment(t, 0.86, 1)))
                .ignoresSafeArea()

            if let plan {
                PrintedCard(plan: plan, choreography: choreography, progress: develop)
                    .frame(width: width, height: width)
                    .position(x: centreX, y: centreY)
                    .shadow(color: .black.opacity(0.22 * travel),
                            radius: 22 * travel, y: 10 * travel)
            }
        }
        // Nothing above the slot's lower lip draws, so the card genuinely comes
        // out of the island rather than appearing beside it.
        .mask(alignment: .bottom) {
            Rectangle().padding(.top, slotBottom)
        }
        .overlay(alignment: .top) {
            IslandShim(width: lerp(IslandMetrics.closedSize.width,
                                   IslandMetrics.openSize.width, open),
                       height: islandHeight,
                       top: islandTop,
                       isWorking: phase == .working)
        }
    }

    private func lerp(_ a: CGFloat, _ b: CGFloat, _ t: Double) -> CGFloat {
        a + (b - a) * CGFloat(t)
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
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
    }
}

/// The black pill standing in for the Dynamic Island.
struct IslandShim: View {
    let width: CGFloat
    let height: CGFloat
    let top: CGFloat
    let isWorking: Bool

    @State private var pulse = false

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2, style: .continuous)
            .fill(Color.black)
            .frame(width: width, height: height)
            .scaleEffect(isWorking && pulse ? 1.035 : 1)
            .offset(y: top)
            .frame(maxWidth: .infinity, alignment: .center)
            .onAppear {
                guard isWorking else { return }
                withAnimation(.easeInOut(duration: 0.62).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
            .allowsHitTesting(false)
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
