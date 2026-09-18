import SwiftUI
import UIKit

/// The glass surface from the design file.
///
/// Mapping the Figma effect onto the platform: Figma's Glass (refraction,
/// dispersion, splay) is its own renderer and has no direct SwiftUI equivalent.
/// iOS 26's Liquid Glass is the real thing and is what the tinted fill is handed
/// to. The five inner shadows in the file are what give the edge its lit rim, so
/// they are reproduced as gradient rim strokes rather than as literal shadows —
/// SwiftUI has no inner shadow primitive, and a stroke is both cheaper and
/// sharper at these radii.
struct GlassSurface: ViewModifier {

    /// `#73FAFF` at 20%, straight from the file.
    var tint: Color = Color(hex: "#73FAFF") ?? .cyan
    var tintOpacity: Double = 0.20
    var cornerRadius: CGFloat = 20
    var isHighlighted: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background {
                ZStack {
                    backdrop
                    shape.fill(tintedFill)
                }
            }
            .overlay { rim }
            .clipShape(shape)          // "Clip content" is on in the file
            .contentShape(shape)
    }

    /// The material itself, untinted — the tint is a separate fill above it, as
    /// in the design file, so the inner shadows sit on the tint and not on glass.
    @ViewBuilder
    private var backdrop: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape.fill(Color.clear)
                .glassEffect(.regular, in: shape)
        } else {
            shape.fill(Material.ultraThin)
        }
        #else
        shape.fill(Material.ultraThin)
        #endif
    }

    /// The tint fill carrying the inner-shadow stack.
    ///
    /// The five shadows from the file, in listed order:
    ///
    ///     y -246  blur 69  white  1%
    ///     y -158  blur 63  white  6%
    ///     y  -89  blur 53  white 10%
    ///     y  -39  blur 39  white 25%
    ///     y  -10  blur 22  white 20%
    ///
    /// Every one is white and offset upward, so together they read as a glow
    /// rising from the bottom inner edge — broad and nearly invisible at the top
    /// of the stack, tight and bright at the bottom.
    ///
    /// Radii are the file's blur halved: Figma states blur the way CSS does, as
    /// roughly twice the Gaussian sigma, while SwiftUI's shadow radius is about
    /// the sigma itself.
    private var tintedFill: some ShapeStyle {
        tint.opacity(tintOpacity)
            .shadow(.inner(color: .white.opacity(0.01), radius: 34.5, y: -246))
            .shadow(.inner(color: .white.opacity(0.06), radius: 31.5, y: -158))
            .shadow(.inner(color: .white.opacity(0.10), radius: 26.5, y: -89))
            .shadow(.inner(color: .white.opacity(0.25), radius: 19.5, y: -39))
            .shadow(.inner(color: .white.opacity(0.20), radius: 11.0, y: -10))
    }

    /// The file lists no stroke; the visible edge comes from the glass itself.
    /// This is a faint stand-in so the surface still reads as an edge on the
    /// material fallback, plus the focus ring.
    private var rim: some View {
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    colors: [Color.white.opacity(0.30), Color.white.opacity(0.06)],
                    startPoint: .top, endPoint: .bottom),
                lineWidth: 0.75)
            if isHighlighted {
                shape.strokeBorder(Color.white.opacity(0.55), lineWidth: 1.5)
            }
        }
        .allowsHitTesting(false)
    }
}

extension View {
    /// The house glass surface, at the design file's values by default.
    func glassSurface(cornerRadius: CGFloat = 20,
                      tint: Color = Color(hex: "#73FAFF") ?? .cyan,
                      tintOpacity: Double = 0.20,
                      isHighlighted: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, tintOpacity: tintOpacity,
                              cornerRadius: cornerRadius,
                              isHighlighted: isHighlighted))
    }
}

/// The stacked-document mark in the upload card.
///
/// Drawn rather than shipped as an asset so it scales cleanly. Replace it with
/// the real artwork by adding `upload-mark` to the asset catalogue — this view
/// prefers it whenever it resolves.
///
/// Laid out at a canonical 92pt and scaled, with every measurement a named
/// constant. Inline arithmetic inside a ViewBuilder is what makes the Swift
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
            sheet(width: Self.sheetWidth * 0.86,
                  height: Self.sheetHeight * 0.92,
                  opacity: 0.55)
                .rotationEffect(.degrees(-9))
                .offset(x: -10, y: -4)

            sheet(width: Self.sheetWidth * 0.93,
                  height: Self.sheetHeight * 0.96,
                  opacity: 0.78)
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
