import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers
#if canImport(UIKit)
import UIKit
#endif

/// Draws a plan into a bitmap.
enum RasterRenderer {

    /// Renders at `pixelSize` square. Returns nil only if a bitmap context
    /// cannot be created, which in practice means an absurd size.
    static func image(for plan: RenderPlan, pixelSize: Int) -> CGImage? {
        let side = max(pixelSize, 16)
        guard let context = CGContext(data: nil, width: side, height: side,
                                      bitsPerComponent: 8, bytesPerRow: 0,
                                      space: CGColorSpaceCreateDeviceRGB(),
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setAllowsAntialiasing(true)
        context.interpolationQuality = .high

        // Plan coordinates run y-down from the top-left; a bitmap context runs
        // y-up from the bottom-left, so the transform flips as it scales.
        let scale = Double(side) / plan.canvasUnits
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: Double(side))
        draw(plan, into: context, transform: transform)
        return context.makeImage()
    }

    static func draw(_ plan: RenderPlan, into context: CGContext, transform: CGAffineTransform) {
        for group in PlanFlattener.flatten(plan) {
            let path = PathGeometry.cgPath(for: group.primitives, transform: transform)
            context.addPath(path)
            context.setFillColor(group.colour.cgColor)
            // Even-odd lets the finder rings carve their own holes, and is
            // identical to non-zero for the grid shapes, which never overlap.
            context.fillPath(using: .evenOdd)
        }
    }

    static func pngData(for plan: RenderPlan, pixelSize: Int) -> Data? {
        guard let image = image(for: plan, pixelSize: pixelSize) else { return nil }
        return pngData(from: image)
    }

    static func pngData(from image: CGImage) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data as CFMutableData, UTType.png.identifier as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }
}

/// Writes a plan as a vector PDF.
enum PDFRenderer {

    static func data(for plan: RenderPlan, pointSize: Double = 512) -> Data? {
        let box = CGRect(x: 0, y: 0, width: pointSize, height: pointSize)
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output as CFMutableData) else { return nil }
        var mediaBox = box
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else { return nil }

        context.beginPDFPage(nil)
        let scale = pointSize / plan.canvasUnits
        // A raw PDF context is y-up, same as a bitmap context.
        let transform = CGAffineTransform(a: scale, b: 0, c: 0, d: -scale, tx: 0, ty: pointSize)
        RasterRenderer.draw(plan, into: context, transform: transform)
        context.endPDFPage()
        context.closePDF()
        return output as Data
    }
}

/// Writes a plan as a standalone SVG document.
enum SVGRenderer {

    static func string(for plan: RenderPlan, pixelSize: Double = 1024) -> String {
        let scale = pixelSize / plan.canvasUnits
        var body = ""
        for group in PlanFlattener.flatten(plan) {
            let data = PathGeometry.svgPathData(for: group.primitives, scale: scale)
            guard !data.isEmpty else { continue }
            body += "  <path fill=\"\(group.colour.hexString)\" fill-rule=\"evenodd\" d=\"\(data)\"/>\n"
        }
        let size = String(format: "%.2f", pixelSize)
        return """
        <?xml version="1.0" encoding="UTF-8"?>
        <svg xmlns="http://www.w3.org/2000/svg" width="\(size)" height="\(size)" \
        viewBox="0 0 \(size) \(size)" shape-rendering="geometricPrecision">
          <title>QR code for \(escape(plan.payload))</title>
        \(body)</svg>
        """
    }

    static func data(for plan: RenderPlan, pixelSize: Double = 1024) -> Data? {
        string(for: plan, pixelSize: pixelSize).data(using: .utf8)
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;")
            .replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;")
            .replacingOccurrences(of: "\"", with: "&quot;")
    }
}
