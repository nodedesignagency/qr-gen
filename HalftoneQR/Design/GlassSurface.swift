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
    /// Figma's Light value, 0...1. Drives how hot the rim reads.
    var light: Double = 0.80
    var isHighlighted: Bool = false

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
    }

    func body(content: Content) -> some View {
        content
            .background { surface }
            .overlay { rim }
            .clipShape(shape)          // "Clip content" is on in the file
            .contentShape(shape)
    }

    @ViewBuilder
    private var surface: some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            shape.fill(Color.clear)
                .glassEffect(.regular.tint(tint.opacity(tintOpacity)), in: shape)
        } else {
            fallbackSurface
        }
        #else
        fallbackSurface
        #endif
    }

    private var fallbackSurface: some View {
        ZStack {
            shape.fill(Material.ultraThin)
            shape.fill(tint.opacity(tintOpacity))
        }
    }

    /// Light arrives at -45°, so the rim is hottest at the top-leading edge and
    /// cools round to a soft bounce at the bottom-trailing one.
    private var rim: some View {
        ZStack {
            shape.strokeBorder(
                LinearGradient(
                    stops: [
                        .init(color: Color.white.opacity(0.90 * light), location: 0.0),
                        .init(color: Color.white.opacity(0.28 * light), location: 0.35),
                        .init(color: Color.white.opacity(0.10 * light), location: 0.62),
                        .init(color: Color.white.opacity(0.45 * light), location: 1.0),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
            shape.inset(by: 1.5)
                .strokeBorder(Color.white.opacity(0.10 * light), lineWidth: 1)
        }
        .overlay {
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
                      light: Double = 0.80,
                      isHighlighted: Bool = false) -> some View {
        modifier(GlassSurface(tint: tint, tintOpacity: tintOpacity,
                              cornerRadius: cornerRadius, light: light,
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
