import CoreText
import SwiftUI
import UIKit

/// Type for the app.
///
/// The design is set in SN Pro, which is not a system face. Until the `.otf`
/// files are dropped into `Resources/Fonts`, every call falls back to the system
/// face at the same size, weight and tracking, so nothing shifts when they
/// arrive. Registration happens at launch, so adding the files is the only step.
enum AppFont {

    /// Registers every font file bundled with the app.
    ///
    /// The project generates its Info.plist, which cannot express the `UIAppFonts`
    /// array, so the files are registered with Core Text at launch instead.
    /// Dropping `SNPro-*.otf` into `Resources/Fonts` is then the only step — no
    /// plist or project edits.
    static func registerBundledFonts() {
        let extensions = ["otf", "ttf", "ttc"]
        var urls: [URL] = []
        for ext in extensions {
            urls += Bundle.main.urls(forResourcesWithExtension: ext, subdirectory: nil) ?? []
        }
        guard !urls.isEmpty else { return }
        // Process scope keeps them out of the system-wide font list.
        CTFontManagerRegisterFontURLs(urls as CFArray, .process, true, nil)
    }

    /// PostScript names, in the order SN Pro ships them.
    private static let faces: [Font.Weight: String] = [
        .regular: "SNPro-Regular",
        .medium: "SNPro-Medium",
        .semibold: "SNPro-Semibold",
        .bold: "SNPro-Bold",
    ]

    private static func isAvailable(_ name: String) -> Bool {
        UIFont(name: name, size: 12) != nil
    }

    static func sn(_ size: CGFloat, weight: Font.Weight = .medium) -> Font {
        if let name = faces[weight], isAvailable(name) {
            return .custom(name, fixedSize: size)
        }
        return .system(size: size, weight: weight)
    }

    /// Figma expresses letter spacing as a percentage of the type size.
    static func tracking(_ percent: Double, at size: CGFloat) -> CGFloat {
        size * percent / 100
    }
}

extension View {
    /// Applies a size, weight and percentage tracking in one go, matching how the
    /// design file specifies type.
    func snType(_ size: CGFloat, weight: Font.Weight = .medium,
                trackingPercent: Double = -1) -> some View {
        font(AppFont.sn(size, weight: weight))
            .tracking(AppFont.tracking(trackingPercent, at: size))
    }
}

extension Color {
    /// `#RGB`, `#RRGGBB` or `#RRGGBBAA`.
    init?(hex: String) {
        guard let rgb = RGB(hex: hex) else { return nil }
        self = rgb.swiftUIColor
    }
}
