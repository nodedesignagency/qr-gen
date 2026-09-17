import CoreGraphics
import Foundation
import ImageIO
import PDFKit
import UniformTypeIdentifiers
import WebKit
#if canImport(UIKit)
import UIKit
#endif

/// Turns whatever the user drops in — PNG, JPEG, HEIC, PDF or SVG — into a
/// bitmap the silhouette extractor can read.
enum ImageDecoder {

    static let supportedTypes: [UTType] = {
        var types: [UTType] = [.png, .jpeg, .heic, .heif, .tiff, .pdf, .image]
        if let svg = UTType("public.svg-image") { types.insert(svg, at: 0) }
        return types
    }()

    /// Decodes raster data. Returns nil for formats that need a renderer, such
    /// as SVG — use `decodeVector` for those.
    static func decode(_ data: Data) -> CGImage? {
        if let source = CGImageSourceCreateWithData(data as CFData, nil),
           CGImageSourceGetCount(source) > 0,
           let image = CGImageSourceCreateImageAtIndex(source, 0, [
               kCGImageSourceShouldCache: true,
               kCGImageSourceCreateThumbnailFromImageAlways: false,
           ] as CFDictionary) {
            return image
        }
        return decodePDF(data)
    }

    /// Renders the first page of a PDF logo at a useful size.
    static func decodePDF(_ data: Data) -> CGImage? {
        guard let document = PDFDocument(data: data), let page = document.page(at: 0) else {
            return nil
        }
        let bounds = page.bounds(for: .mediaBox)
        guard bounds.width > 0, bounds.height > 0 else { return nil }
        let side = 1024.0
        let scale = side / max(bounds.width, bounds.height)
        let width = Int((bounds.width * scale).rounded())
        let height = Int((bounds.height * scale).rounded())
        guard width > 0, height > 0,
              let context = CGContext(data: nil, width: width, height: height,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.scaleBy(x: scale, y: scale)
        context.translateBy(x: -bounds.minX, y: -bounds.minY)
        page.draw(with: .mediaBox, to: context)
        return context.makeImage()
    }

    static func isVector(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "svg"
    }

    /// Rasterises an SVG.
    ///
    /// iOS has no public SVG rasteriser, so this hands the markup to a web view
    /// and snapshots it. The view is offscreen and never sees the network.
    @MainActor
    static func decodeSVG(_ data: Data, side: CGFloat = 1024) async -> CGImage? {
        guard let markup = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .isoLatin1) else { return nil }

        let configuration = WKWebViewConfiguration()
        configuration.suppressesIncrementalRendering = true
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: side, height: side),
                                configuration: configuration)
        webView.isOpaque = false
        webView.backgroundColor = .clear
        webView.scrollView.backgroundColor = .clear

        let html = """
        <!DOCTYPE html><html><head><meta name="viewport" content="width=\(Int(side))">
        <style>html,body{margin:0;padding:0;background:transparent;width:\(Int(side))px;height:\(Int(side))px;\
        display:flex;align-items:center;justify-content:center;overflow:hidden}
        svg{max-width:100%;max-height:100%;width:100%;height:100%}</style></head>
        <body>\(markup)</body></html>
        """
        webView.loadHTMLString(html, baseURL: nil)

        // Give the web view a moment to lay out; snapshotting too early yields blank.
        for _ in 0..<40 {
            try? await Task.sleep(nanoseconds: 50_000_000)
            if !webView.isLoading { break }
        }
        try? await Task.sleep(nanoseconds: 120_000_000)

        let configurationSnapshot = WKSnapshotConfiguration()
        configurationSnapshot.rect = CGRect(x: 0, y: 0, width: side, height: side)
        configurationSnapshot.afterScreenUpdates = true

        return await withCheckedContinuation { continuation in
            webView.takeSnapshot(with: configurationSnapshot) { image, _ in
                continuation.resume(returning: image?.cgImage)
            }
        }
    }

    /// Loads any supported file, picking the right path for its type.
    @MainActor
    static func load(contentsOf url: URL) async -> CGImage? {
        let needsScope = url.startAccessingSecurityScopedResource()
        defer { if needsScope { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else { return nil }
        if isVector(url) { return await decodeSVG(data) }
        return decode(data)
    }
}
