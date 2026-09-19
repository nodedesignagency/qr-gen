import Foundation

/// One of the four finishes offered at export.
///
/// They differ only in palette, so all four are planned from the same symbol and
/// each is verified independently before it is offered.
struct ExportVariant: Identifiable, Sendable {

    enum Kind: String, CaseIterable, Sendable {
        case ink, brand, inverse, duotone

        var title: String {
            switch self {
            case .ink: return "Ink"
            case .brand: return "Brand"
            case .inverse: return "Inverse"
            case .duotone: return "Duotone"
            }
        }

        var subtitle: String {
            switch self {
            case .ink: return "Neutral black"
            case .brand: return "Logo colour"
            case .inverse: return "Light on dark"
            case .duotone: return "Two-tone structure"
            }
        }

        func palette(brand: RGB) -> Palette {
            switch self {
            case .ink:
                return .monochrome()
            case .brand:
                let readable = DominantColour.readableInk(brand, onPaper: .paper)
                return Palette(paper: .paper, ink: readable, structure: readable, art: readable)
            case .inverse:
                let field = RGB(red: 0.043, green: 0.047, blue: 0.055)
                let readable = DominantColour.readableInk(brand, onPaper: field, minimumRatio: 4.5)
                return Palette(paper: field, ink: .paper, structure: readable, art: .paper)
            case .duotone:
                // The mark first: the centres and the structure in the neutral
                // ink, the mark in its own colour, and the centres beneath the
                // mark so it reads as one shape. Colour does the separating;
                // opacity cannot — see Tools/validation/focus.py.
                let readable = DominantColour.readableInk(brand, onPaper: .paper)
                return Palette(paper: .paper, ink: .ink, structure: .ink, art: readable, inkUnderArt: true)
            }
        }
    }

    let id: Kind
    let plan: RenderPlan
    let report: VerificationReport
    /// True when this finish needed a weaker logo than the others to decode.
    let wasReduced: Bool

    var kind: Kind { id }
}

/// The files produced for a chosen variant.
struct ExportBundle: Sendable {
    let pngURL: URL
    let svgURL: URL
    let pdfURL: URL
    let animationURL: URL?

    var allURLs: [URL] { [pngURL, svgURL, pdfURL] + (animationURL.map { [$0] } ?? []) }
}

enum ExportWriter {

    /// Writes the three still formats, plus the animation when one was rendered.
    static func write(variant: ExportVariant, basename: String,
                      animation: Data? = nil,
                      pngPixels: Int = 2048) throws -> ExportBundle {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("exports", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let stem = sanitise(basename) + "-" + variant.kind.rawValue
        let png = directory.appendingPathComponent(stem + ".png")
        let svg = directory.appendingPathComponent(stem + ".svg")
        let pdf = directory.appendingPathComponent(stem + ".pdf")

        guard let pngData = RasterRenderer.pngData(for: variant.plan, pixelSize: pngPixels) else {
            throw ExportError.renderFailed
        }
        try pngData.write(to: png, options: .atomic)

        guard let svgData = SVGRenderer.data(for: variant.plan) else { throw ExportError.renderFailed }
        try svgData.write(to: svg, options: .atomic)

        guard let pdfData = PDFRenderer.data(for: variant.plan) else { throw ExportError.renderFailed }
        try pdfData.write(to: pdf, options: .atomic)

        var animationURL: URL?
        if let animation {
            let url = directory.appendingPathComponent(stem + ".gif")
            try animation.write(to: url, options: .atomic)
            animationURL = url
        }

        return ExportBundle(pngURL: png, svgURL: svg, pdfURL: pdf, animationURL: animationURL)
    }

    enum ExportError: Error, LocalizedError {
        case renderFailed
        var errorDescription: String? { "Could not render the export." }
    }

    /// Turns a URL into something safe and recognisable as a filename.
    static func sanitise(_ text: String) -> String {
        var slug = text.lowercased()
        for prefix in ["https://", "http://", "www."] where slug.hasPrefix(prefix) {
            slug.removeFirst(prefix.count)
        }
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-"))
        slug = String(slug.unicodeScalars.map { allowed.contains($0) ? Character($0) : "-" })
        while slug.contains("--") { slug = slug.replacingOccurrences(of: "--", with: "-") }
        slug = slug.trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        if slug.isEmpty { slug = "qr" }
        return String(slug.prefix(48))
    }
}
