import SwiftUI
import UIKit

/// The glass surface from the design file.
///
/// Mapping Figma's glass onto the platform:
///
/// - The tint goes *into* the glass rather than sitting on top of it as its own
///   fill. Layering 20% cyan over frosted glass is what made the first attempt
///   read as flat milk instead of a pane you can see through.
/// - The file's Frost is 4 out of 100 with Refraction at 80 — nearly clear
///   glass. `Glass.regular` is the frostiest variant and was the wrong choice;
///   `.clear` is the match. If it ever wants more diffusion, that is the dial.
/// - The five inner shadows live in `InnerGlow`, and only the upload card asks
///   for them: the file has them switched off on the URL field.
struct GlassSurface: ViewModifier {

    /// `#73FAFF` at 20%, straight from the file.
    var tint: Color = Color(hex: "#73FAFF") ?? .cyan
    var tintOpacity: Double = 0.20
    var cornerRadius: CGFloat = 20
    /// The five-inner-shadow stack. Off by default, as the URL field has it off.
    var innerGlow: Bool = false
    var isHighlighted: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { backdrop }
            .overlay {
                if innerGlow {
                    InnerGlow(cornerRadius: cornerRadius)
                        .allowsHitTesting(false)
                }
            }
            .overlay { rim }
            .clipShape(shape)          // "Clip content" is on in the file
            .contentShape(shape)
    }

    @ViewBuilder
    private var backdrop: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape.fill(Color.clear)
                .glassEffect(.clear.tint(tint.opacity(tintOpacity)), in: shape)
        } else {
            fallbackBackdrop
        }
        #else
        fallbackBackdrop
        #endif
    }

    /// Below iOS 26 there is no refraction to be had, so a thin material carries
    /// the tint instead.
    private var fallbackBackdrop: some View {
        ZStack {
            shape.fill(Material.ultraThin)
            shape.fill(tint.opacity(tintOpacity))
        }
    }

    /// The file lists no stroke; the lit edge comes from the glass itself. This
    /// hairline only has to hold the edge together on the material fallback, and
    /// to carry the focus ring.
    private var rim: some View {
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.28), Color.white.opacity(0.05)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
            if isHighlighted {
                shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

/// The five inner shadows from the design file, as a vertical gradient.
///
///     y -246  blur 69  white  1%
///     y -158  blur 63  white  6%
///     y  -89  blur 53  white 10%
///     y  -39  blur 39  white 25%
///     y  -10  blur 22  white 20%
///
/// All white, all offset upward, so together they read as a glow rising from the
/// bottom inner edge. Rather than stacking five `ShadowStyle.inner` passes, the
/// combined profile is evaluated directly: the same arithmetic in one gradient,
/// and it cannot silently fail to draw over a transparent fill.
///
/// The profile is computed against the live height, which matters here. These
/// offsets reach 246pt, so on the 200pt card the glow decays to almost nothing
/// by the top, while on a 58pt field the two strongest would wash the whole
/// surface evenly — which is exactly why the file switches them off there.
struct InnerGlow: View {
    var cornerRadius: CGFloat = 20

    /// Opacity, blur and upward offset, in the file's order.
    private static let shadows: [(opacity: Double, blur: Double, offset: Double)] = [
        (0.01, 69, 246),
        (0.06, 63, 158),
        (0.10, 53, 89),
        (0.25, 39, 39),
        (0.20, 22, 10),
    ]

    var body: some View {
        GeometryReader { geometry in
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(LinearGradient(stops: Self.stops(forHeight: geometry.size.height),
                                     startPoint: .top, endPoint: .bottom))
        }
    }

    /// Samples the combined profile down the surface.
    static func stops(forHeight height: CGFloat) -> [Gradient.Stop] {
        let samples = 14
        return (0...samples).map { index in
            let location = Double(index) / Double(samples)
            let distance = Double(height) * (1 - location)
            return Gradient.Stop(color: Color.white.opacity(alpha(atDistance: distance)),
                                 location: location)
        }
    }

    /// Alpha compositing of all five shadows at a distance from the bottom edge.
    static func alpha(atDistance distance: Double) -> Double {
        var transmitted = 1.0
        for shadow in shadows {
            // Each shadow fades out past its own offset, and its blur also bleeds
            // back across the bottom edge, so the peak sits just inside it.
            let ramp = min(max(0.5 - (distance - shadow.offset) / shadow.blur, 0), 1)
            let edge = min(max(0.5 + distance / shadow.blur, 0), 1)
            transmitted *= 1 - shadow.opacity * ramp * edge
        }
        return 1 - transmitted
    }
}

extension View {
    /// The house glass surface, at the design file's values by default.
    func glassSurface(cornerRadius: CGFloat = 20,
                      tint: Color = Color(hex: "#73FAFF") ?? .cyan,
                      tintOpacity: Double = 0.20,
                      innerGlow: Bool = false,
                      isHighlighted: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, tintOpacity: tintOpacity,
                              cornerRadius: cornerRadius, innerGlow: innerGlow,
                              isHighlighted: isHighlighted))
    }
}

/// The stacked-document mark in the upload card.
///
/// Prefers the artwork in the asset catalogue and falls back to a drawn stand-in
/// so the layout never breaks if the asset is missing.
///
/// Laid out at a canonical 92pt and scaled, with every measurement a named
/// constant — inline arithmetic inside a ViewBuilder is what makes the Swift
/// type-checker give up on a view like this.
struct UploadMark: View {
    var size: CGFloat = 92

    private static let canonical: CGFloat = 92
    private static let sheetWidth: CGFloat = 52
    private static let sheetHeight: CGFloat = 62

    var body: some View {
        Group {
            if UIImage(named: "upload-mark") != nil {
                Image("upload-mark")
                    .resizable()
                    .scaledToFit()
            } else {
                drawn
                    .frame(width: Self.canonical, height: Self.canonical)
                    .scaleEffect(size / Self.canonical)
            }
        }
        .frame(width: size, height: size)
    }

    private var drawn: some View {
        ZStack {
            sheet(width: Self.sheetWidth * 0.86, height: Self.sheetHeight * 0.92, opacity: 0.55)
                .rotationEffect(.degrees(-9))
                .offset(x: -10, y: -4)

            sheet(width: Self.sheetWidth * 0.93, height: Self.sheetHeight * 0.96, opacity: 0.78)
                .rotationEffect(.degrees(-3))
                .offset(x: -4, y: -2)

            frontSheet
                .offset(x: 6, y: 2)

            badge
                .offset(x: 19, y: 21)
        }
        .shadow(color: Color.black.opacity(0.16), radius: 5, y: 2)
    }

    private var frontSheet: some View {
        ZStack {
            sheet(width: Self.sheetWidth, height: Self.sheetHeight, opacity: 1)
            VStack(spacing: 4) {
                rule(width: 22)
                rule(width: 15)
            }
            .offset(y: -21)
            Image(systemName: "photo.fill")
                .font(.system(size: 16))
                .foregroundStyle(Color.black.opacity(0.16))
                .offset(y: 4)
        }
    }

    private var badge: some View {
        Circle()
            .fill(Color.white)
            .frame(width: 24, height: 24)
            .overlay {
                Image(systemName: "arrow.up")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(Color.black.opacity(0.45))
            }
    }

    private func sheet(width: CGFloat, height: CGFloat, opacity: Double) -> some View {
        RoundedRectangle(cornerRadius: 7, style: .continuous)
            .fill(Color.white.opacity(opacity))
            .frame(width: width, height: height)
    }

    private func rule(width: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: 1.5, style: .continuous)
            .fill(Color.black.opacity(0.12))
            .frame(width: width, height: 3)
    }
}
