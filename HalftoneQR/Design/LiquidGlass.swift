import SwiftUI

/// Liquid Glass where the OS has it, and a material that reads the same way
/// where it does not.
///
/// The bottom bar and the floating controls are the only chrome in the app, so
/// they are the only things that get glass. Content never sits on it.
struct LiquidGlassModifier<S: Shape>: ViewModifier {
    let shape: S
    var tint: Color?
    var isInteractive: Bool

    func body(content: Content) -> some View {
        // The runtime check alone is not enough: `Glass` does not exist in SDKs
        // before iOS 26, so the compile-time gate has to come first. Xcode 26 is
        // the first release to ship Swift 6.2.
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            content.glassEffect(glass, in: shape)
        } else {
            fallback(content)
        }
        #else
        fallback(content)
        #endif
    }

    /// A material and a hairline, which is what Liquid Glass degrades to.
    private func fallback(_ content: Content) -> some View {
        content
            .background(.ultraThinMaterial, in: shape)
            .background(tint?.opacity(0.14) ?? Color.clear, in: shape)
            .overlay(shape.stroke(Theme.hairlineStrong, lineWidth: 0.5))
    }

    #if compiler(>=6.2)
    @available(iOS 26.0, *)
    private var glass: Glass {
        var glass = Glass.regular
        if let tint { glass = glass.tint(tint.opacity(0.5)) }
        if isInteractive { glass = glass.interactive() }
        return glass
    }
    #endif
}

extension View {
    /// Applies Liquid Glass in the given shape.
    func liquidGlass(_ shape: some Shape, tint: Color? = nil,
                     interactive: Bool = false) -> some View {
        modifier(LiquidGlassModifier(shape: shape, tint: tint, isInteractive: interactive))
    }

    /// Groups sibling glass elements so the OS can merge and separate them as
    /// they move. A no-op before iOS 26.
    @ViewBuilder
    func glassGroup(spacing: CGFloat = 12) -> some View {
        #if compiler(>=6.2)
        if #available(iOS 26.0, *) {
            GlassEffectContainer(spacing: spacing) { self }
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// A capsule button that takes the system's glass treatment when available.
struct GlassButtonStyle: ButtonStyle {
    var prominent: Bool = false
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(prominent ? Theme.background : Theme.primary)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.controlHeight)
            .background {
                if prominent {
                    Capsule().fill(tint ?? Theme.primary)
                } else {
                    Capsule().fill(.clear).liquidGlass(Capsule(), tint: tint, interactive: true)
                }
            }
            .contentShape(Capsule())
            .scaleEffect(configuration.isPressed ? 0.975 : 1)
            // Mechanical, not springy: a short linear settle.
            .animation(.easeOut(duration: 0.12), value: configuration.isPressed)
    }
}
