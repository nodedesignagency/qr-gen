import SwiftUI

/// The app's visual constants.
///
/// Near-black rather than pure black, one accent colour taken from the user's own
/// artwork, hairline borders instead of filled cards, and no gradients or
/// shadows anywhere. Everything that is a value — a label, a count, the decoded
/// string — is monospaced; everything that is prose is not.
enum Theme {

    // MARK: Surfaces

    /// Not #000. Pure black kills the sense of a lit surface and makes the
    /// hairlines look like tears rather than edges.
    static let background = Color(red: 0.043, green: 0.047, blue: 0.055)
    static let elevated = Color(red: 0.071, green: 0.075, blue: 0.086)
    static let sunken = Color(red: 0.027, green: 0.031, blue: 0.039)

    // MARK: Ink

    static let primary = Color(red: 0.949, green: 0.957, blue: 0.969)
    static let secondary = Color(red: 0.541, green: 0.565, blue: 0.608)
    static let tertiary = Color(red: 0.353, green: 0.376, blue: 0.420)

    // MARK: Lines

    static let hairline = Color.white.opacity(0.10)
    static let hairlineStrong = Color.white.opacity(0.18)

    // MARK: Signal

    static let defaultAccent = Color(red: 0.365, green: 0.569, blue: 1.0)
    static let positive = Color(red: 0.310, green: 0.851, blue: 0.573)
    static let caution = Color(red: 0.980, green: 0.741, blue: 0.318)
    static let negative = Color(red: 0.996, green: 0.408, blue: 0.408)

    // MARK: Metrics

    static let gutter: CGFloat = 20
    static let cornerRadius: CGFloat = 20
    static let controlHeight: CGFloat = 52
}

extension Font {
    /// Monospaced, for anything that is a value rather than a sentence.
    static func mono(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        .system(size: size, weight: weight, design: .monospaced)
    }

    /// The small uppercase labels that sit at the edges of every screen.
    static var railLabel: Font { .system(size: 10, weight: .semibold, design: .monospaced) }
    static var valueLabel: Font { .system(size: 13, weight: .medium, design: .monospaced) }
}

extension View {
    /// A hairline border in the house style.
    func hairlineBorder(_ shape: some InsettableShape, colour: Color = Theme.hairline) -> some View {
        overlay(shape.strokeBorder(colour, lineWidth: 0.5))
    }

    /// Uppercased, tracked-out monospaced caption.
    func railLabelStyle(_ colour: Color = Theme.tertiary) -> some View {
        font(.railLabel)
            .tracking(1.2)
            .textCase(.uppercase)
            .foregroundStyle(colour)
    }
}

/// The accent colour in play, derived from the user's artwork when there is any.
///
/// Threaded through the environment so every control picks it up without the
/// screens having to pass it down by hand.
private struct AccentKey: EnvironmentKey {
    static let defaultValue = Theme.defaultAccent
}

extension EnvironmentValues {
    var signalAccent: Color {
        get { self[AccentKey.self] }
        set { self[AccentKey.self] = newValue }
    }
}
