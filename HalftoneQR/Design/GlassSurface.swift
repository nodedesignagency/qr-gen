import SwiftUI

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
            shape.fill(.clear)
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
            shape.fill(.ultraThinMaterial)
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
                        .init(color: .white.opacity(0.90 * light), location: 0.0),
                        .init(color: .white.opacity(0.28 * light), location: 0.35),
                        .init(color: .white.opacity(0.10 * light), location: 0.62),
                        .init(color: .white.opacity(0.45 * light), location: 1.0),
                    ],
                    startPoint: .topLeading, endPoint: .bottomTrailing),
                lineWidth: 1)
            shape.inset(by: 1.5)
                .strokeBorder(.white.opacity(0.10 * light), lineWidth: 1)
        }
        .overlay {
            if isHighlighted {
                shape.strokeBorder(.white.opacity(0.55), lineWidth: 1.5)
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
/// Drawn rather than shipped as an asset so it scales cleanly and picks up the
/// surrounding tint. Replace with the real artwork by dropping it into the asset
/// catalogue as `upload-mark` — `UploadMark` prefers it when present.
struct UploadMark: View {
    var size: CGFloat = 92

    var body: some View {
        Group {
            if UIImage(named: "upload-mark") != nil {
                Image("upload-mark").resizable().scaledToFit()
            } else {
                drawn
            }
        }
        .frame(width: size, height: size)
    }

    private var drawn: some View {
        GeometryReader { geometry in
            let side = min(geometry.size.width, geometry.size.height)
            let sheet = side * 0.62
            ZStack {
                // Two sheets behind, fanned out.
                sheetShape(width: sheet * 0.86, height: sheet * 1.06,
                           fill: .white.opacity(0.55))
                    .rotationEffect(.degrees(-9))
                    .offset(x: -side * 0.10, y: -side * 0.045)
                sheetShape(width: sheet * 0.92, height: sheet * 1.10,
                           fill: .white.opacity(0.78))
                    .rotationEffect(.degrees(-3))
                    .offset(x: -side * 0.035, y: -side * 0.015)
                // The front sheet, with the image glyph and the upload badge.
                ZStack {
                    sheetShape(width: sheet, height: sheet * 1.16, fill: .white)
                    VStack(spacing: sheet * 0.07) {
                        RoundedRectangle(cornerRadius: sheet * 0.05)
                            .fill(.black.opacity(0.13))
                            .frame(width: sheet * 0.42, height: sheet * 0.055)
                        RoundedRectangle(cornerRadius: sheet * 0.05)
                            .fill(.black.opacity(0.10))
                            .frame(width: sheet * 0.28, height: sheet * 0.055)
                    }
                    .offset(y: -sheet * 0.36)
                    Image(systemName: "photo.fill")
                        .font(.system(size: sheet * 0.30))
                        .foregroundStyle(.black.opacity(0.16))
                        .offset(y: sheet * 0.06)
                }
                .offset(x: side * 0.06, y: side * 0.02)

                Circle()
                    .fill(.white)
                    .frame(width: side * 0.26, height: side * 0.26)
                    .overlay {
                        Image(systemName: "arrow.up")
                            .font(.system(size: side * 0.13, weight: .bold))
                            .foregroundStyle(.black.opacity(0.42))
                    }
                    .offset(x: side * 0.20, y: side * 0.22)
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
            .shadow(color: .black.opacity(0.14), radius: side * 0.05, y: side * 0.02)
        }
    }

    private func sheetShape(width: CGFloat, height: CGFloat, fill: Color) -> some View {
        RoundedRectangle(cornerRadius: width * 0.13, style: .continuous)
            .fill(fill)
            .frame(width: width, height: height)
    }
}
