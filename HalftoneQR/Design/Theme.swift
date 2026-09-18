import SwiftUI

/// The app's visual constants.
///
/// The symbol is the hero: it sits on a bright paper card that dominates the
/// screen, and everything else is small, quiet and pushed to the edges. Near
/// black rather than pure black, one accent colour taken from the user's own
/// artwork, hairline borders, and no gradients or shadows anywhere.
enum Theme {

    // MARK: Surfaces

    /// Not #000. Pure black kills the sense of a lit surface and makes the
    /// hairlines look like tears rather than edges.
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let elevated = Color(red: 0.086, green: 0.090, blue: 0.102)
    static let sunken = Color(red: 0.031, green: 0.035, blue: 0.043)

    // MARK: Ink

    static let primary = Color(red: 0.961, green: 0.969, blue: 0.980)
    static let secondary = Color(red: 0.569, green: 0.596, blue: 0.639)
    static let tertiary = Color(red: 0.365, green: 0.388, blue: 0.435)

    // MARK: Lines

    static let hairline = Color.white.opacity(0.09)
    static let hairlineStrong = Color.white.opacity(0.16)

    // MARK: Signal

    static let defaultAccent = Color(red: 0.365, green: 0.569, blue: 1.0)
    static let positive = Color(red: 0.310, green: 0.851, blue: 0.573)
    static let caution = Color(red: 0.980, green: 0.741, blue: 0.318)
    static let negative = Color(red: 0.996, green: 0.408, blue: 0.408)

    // MARK: Metrics

    static let gutter: CGFloat = 22
    /// The paper card the symbol sits on. Generous, like a physical card.
    static let cardRadius: CGFloat = 34
    static let cardInset: CGFloat = 20
    static let controlHeight: CGFloat = 58
    static let circleControl: CGFloat = 54
}

extension Font {
    /// Monospaced, for anything that is a value rather than a sentence.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The screen title. Clean sans, not mono — mono is for values.
    static var screenTitle: Font { .system(size: 26, weight: .semibold) }
    /// The small uppercase labels that sit at the edges of every screen.
    static var railLabel: Font { .system(size: 10, weight: .semibold, design: .monospaced) }
    static var valueLabel: Font { .system(size: 13, weight: .medium, design: .monospaced) }
    /// Labels under the circular controls.
    static var controlLabel: Font { .system(size: 11, weight: .medium) }
}

extension View {
    /// A hairline border in the house style.
    func hairlineBorder(_ shape: some InsettableShape, colour: Color = Theme.hairline) -> some View {
        overlay(shape.strokeBorder(colour, lineWidth: 0.5))
    }

    /// Uppercased, tracked-out monospaced caption.
    func railLabelStyle(_ colour: Color = Theme.tertiary) -> some View {
        font(.railLabel)
            .tracking(1.3)
            .textCase(.uppercase)
            .foregroundStyle(colour)
    }
}

/// The accent colour in play, derived from the user's artwork when there is any.
private struct AccentKey: EnvironmentKey {
    static let defaultValue = Theme.defaultAccent
}

extension EnvironmentValues {
    var signalAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
