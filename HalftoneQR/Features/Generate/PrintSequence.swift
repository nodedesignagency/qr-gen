import SwiftUI
import UIKit

/// Where the generate animation has got to.
///
/// The develop passes are driven by the verify loop's own attempt log, so what
/// plays is the work that actually happened: one clean print when the first
/// render decodes, a visible re-exposure each time it did not.
enum GeneratePhase: Equatable {
    case idle
    /// The slot widens.
    case opening
    /// The blank card feeds out of the slot.
    case feeding
    /// A pass developing, indexed into the attempt log.
    case developing(pass: Int)
    /// That pass failed to decode; the print dims before going again.
    case reExposing(pass: Int)
    /// It scanned. The card settles and the slot closes.
    case verified
    /// The card travels to where the next screen will hold it.
    case handoff

    var isRunning: Bool { self != .idle }

    var developPass: Int? {
        switch self {
        case .developing(let pass), .reExposing(let pass): return pass
        default: return nil
        }
    }
}

/// Geometry for the Dynamic Island.
///
/// An app cannot animate the real island — it belongs to the system, and
/// ActivityKit only ever hands it content, never frame-by-frame control. So this
/// draws its own black pill in the same place. The real island is opaque black,
/// so a black shape growing out from behind it reads as one object. On devices
/// without an island it is simply a floating pill, which still reads as a slot.
enum IslandMetrics {
    static let closedSize = CGSize(width: 126, height: 37)
    static let openSize = CGSize(width: 212, height: 74)
    static let topInsetFromScreen: CGFloat = 11

    /// Island devices report a noticeably deeper top inset than notched ones.
    static func hasIsland(topSafeArea: CGFloat) -> Bool { topSafeArea >= 51 }

    static func size(open: Bool) -> CGSize { open ? openSize : closedSize }

    /// Bottom edge of the slot, in screen coordinates.
    static func slotBottom(open: Bool, topSafeArea: CGFloat) -> CGFloat {
        let top = hasIsland(topSafeArea: topSafeArea) ? topInsetFromScreen : topSafeArea - 6
        return top + size(open: open).height
    }
}

/// The full-screen generate animation.
struct PrintSequenceOverlay: View {
    let phase: GeneratePhase
    let plan: RenderPlan?
    let choreography: Choreography
    let accent: Color

    @State private var developStart: Date?

    private let cardWidth: CGFloat = 353
    private let developDuration: Double = 0.95

    var body: some View {
        GeometryReader { geometry in
            let topInset = geometry.safeAreaInsets.top
            let layout = CardLayout(phase: phase,
                                    screen: geometry.size,
                                    topSafeArea: topInset,
                                    cardWidth: cardWidth)
            ZStack(alignment: .top) {
                Color.black
                    .opacity(phase == .idle ? 0 : 0.34)
                    .ignoresSafeArea()

                cardLayer(layout: layout)
                    .mask(alignment: .bottom) {
                        // Nothing above the slot's lower lip draws, so the card
                        // genuinely appears to come out of the island.
                        Rectangle().padding(.top, layout.slotBottom)
                    }

                IslandShim(isOpen: phase != .idle && phase != .handoff,
                           topSafeArea: topInset,
                           accent: accent,
                           showsVerified: phase == .verified)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .ignoresSafeArea()
        .onChange(of: phase) { _, new in
            if case .developing = new { developStart = .now }
        }
    }

    /// Only a live develop needs the display link; every other phase is a static
    /// frame, so the timeline is torn down the moment the pass lands.
    @ViewBuilder
    private func cardLayer(layout: CardLayout) -> some View {
        if let plan {
            if case .developing = phase, let developStart {
                TimelineView(.animation) { timeline in
                    let elapsed = timeline.date.timeIntervalSince(developStart)
                    let progress = min(max(elapsed / developDuration, 0), 1)
                    positioned(plan: plan, layout: layout, progress: progress)
                }
            } else {
                positioned(plan: plan, layout: layout, progress: staticProgress)
            }
        }
    }

    private func positioned(plan: RenderPlan, layout: CardLayout, progress: Double) -> some View {
        PrintedCard(plan: plan,
                    choreography: choreography,
                    progress: progress,
                    dimmed: isReExposing)
            .frame(width: cardWidth, height: cardWidth)
            .scaleEffect(layout.scale)
            .rotationEffect(.degrees(layout.rotation))
            .shadow(color: .black.opacity(layout.shadowOpacity),
                    radius: layout.shadowRadius, y: layout.shadowRadius * 0.55)
            .offset(y: layout.topY)
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.5, dampingFraction: 0.82), value: phase)
    }

    private var isReExposing: Bool {
        if case .reExposing = phase { return true }
        return false
    }

    /// Where a non-developing phase holds the print.
    private var staticProgress: Double {
        switch phase {
        case .idle, .opening, .feeding: return 0
        default: return 1
        }
    }
}

/// Where the card sits, how big it is and how hard it casts, for each phase.
struct CardLayout {
    let topY: CGFloat
    let scale: CGFloat
    let rotation: Double
    let shadowRadius: CGFloat
    let shadowOpacity: Double
    let slotBottom: CGFloat

    init(phase: GeneratePhase, screen: CGSize, topSafeArea: CGFloat, cardWidth: CGFloat) {
        let isOpen = phase != .idle && phase != .handoff
        slotBottom = IslandMetrics.slotBottom(open: isOpen, topSafeArea: topSafeArea)

        switch phase {
        case .idle, .opening:
            // Tucked entirely inside the machine.
            scale = 0.55
            topY = slotBottom - cardWidth * 0.55
            rotation = 0
            shadowRadius = 0
            shadowOpacity = 0
        case .feeding:
            scale = 0.55
            topY = slotBottom - 10
            rotation = -0.6
            shadowRadius = 10
            shadowOpacity = 0.22
        case .developing, .reExposing:
            scale = 0.72
            topY = slotBottom + 22
            rotation = 0.4
            shadowRadius = 18
            shadowOpacity = 0.26
        case .verified:
            scale = 0.94
            topY = max(slotBottom + 46, screen.height * 0.22)
            rotation = 0
            shadowRadius = 26
            shadowOpacity = 0.30
        case .handoff:
            scale = 1.0
            topY = screen.height * 0.24
            rotation = 0
            shadowRadius = 30
            shadowOpacity = 0.24
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
    let dimmed: Bool

    var body: some View {
        ModuleResolveCanvas(plan: plan, progress: progress, choreography: choreography)
            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay {
                // A failed pass flares and drops back before the machine goes
                // again, so a weaker logo is something you watch happen.
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(Color.white.opacity(dimmed ? 0.55 : 0))
            }
            .animation(.easeOut(duration: 0.22), value: dimmed)
    }
}

/// The black pill standing in for the Dynamic Island.
struct IslandShim: View {
    let isOpen: Bool
    let topSafeArea: CGFloat
    let accent: Color
    let showsVerified: Bool

    var body: some View {
        let size = IslandMetrics.size(open: isOpen)
        let top = IslandMetrics.hasIsland(topSafeArea: topSafeArea)
            ? IslandMetrics.topInsetFromScreen
            : topSafeArea - 6

        RoundedRectangle(cornerRadius: size.height / 2, style: .continuous)
            .fill(Color.black)
            .frame(width: size.width, height: size.height)
            .overlay {
                if showsVerified {
                    HStack(spacing: 7) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(accent)
                        Text("Verified")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                    }
                    .transition(.opacity)
                }
            }
            .offset(y: top)
            .frame(maxWidth: .infinity, alignment: .center)
            .animation(.spring(response: 0.42, dampingFraction: 0.78), value: isOpen)
            .animation(.easeOut(duration: 0.2), value: showsVerified)
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
