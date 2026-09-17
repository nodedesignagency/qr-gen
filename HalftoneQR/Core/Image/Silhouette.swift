import CoreGraphics
import Foundation

/// A grayscale ink map sampled from the user's artwork.
///
/// Values run 0 (paper) to 1 (ink). Everything downstream works from this, so the
/// planner never has to care whether the source was a transparent PNG, a flat
/// JPEG or a rasterised SVG.
struct Silhouette: Sendable {

    let width: Int
    let height: Int
    /// Row-major coverage, `width * height` entries in 0...1.
    let coverage: [Float]
    /// Where the ink actually sits, in normalised 0...1 image coordinates.
    let inkBounds: CGRect
    /// True when the ink map came from an alpha channel rather than luminance.
    let usedAlpha: Bool

    static let empty = Silhouette(width: 1, height: 1, coverage: [0],
                                  inkBounds: CGRect(x: 0, y: 0, width: 1, height: 1),
                                  usedAlpha: false)

    /// Bilinear sample in normalised coordinates, clamped at the edges.
    func sample(u: Double, v: Double) -> Float {
        guard width > 1, height > 1 else { return coverage.first ?? 0 }
        let x = min(max(u, 0), 1) * Double(width - 1)
        let y = min(max(v, 0), 1) * Double(height - 1)
        let x0 = Int(x), y0 = Int(y)
        let x1 = min(x0 + 1, width - 1), y1 = min(y0 + 1, height - 1)
        let fx = Float(x - Double(x0)), fy = Float(y - Double(y0))
        let top = coverage[y0 * width + x0] * (1 - fx) + coverage[y0 * width + x1] * fx
        let bottom = coverage[y1 * width + x0] * (1 - fx) + coverage[y1 * width + x1] * fx
        return top * (1 - fy) + bottom * fy
    }

    /// Samples in the coordinate space of the ink bounding box, so artwork with
    /// generous padding still fills the symbol.
    func sampleFitted(u: Double, v: Double, padding: Double = 0.04) -> Float {
        let box = inkBounds
        guard box.width > 0, box.height > 0 else { return 0 }
        // Fit the longer edge so the aspect ratio is preserved.
        let span = max(box.width, box.height) * (1 + padding * 2)
        let centreX = box.midX, centreY = box.midY
        let sourceU = centreX + (u - 0.5) * span
        let sourceV = centreY + (v - 0.5) * span
        guard sourceU >= 0, sourceU <= 1, sourceV >= 0, sourceV <= 1 else { return 0 }
        return sample(u: sourceU, v: sourceV)
    }
}

enum SilhouetteExtractor {

    /// Resolution the artwork is reduced to before planning. Fine enough for the
    /// densest symbol we will ever render, small enough to stay instant.
    static let workingSize = 480

    /// Builds an ink map from a bitmap.
    ///
    /// Alpha wins when the image actually has transparency, because a logo
    /// delivered as a transparent PNG carries its silhouette there exactly.
    /// Otherwise the image is thresholded on luminance, with the polarity chosen
    /// from the corners so light-on-dark artwork is not inverted.
    static func silhouette(from image: CGImage) -> Silhouette {
        let side = workingSize
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
        // The context must not outlive the buffer pointer, so all drawing happens
        // inside the withUnsafeMutableBytes body.
        let drew = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(data: buffer.baseAddress, width: side, height: side,
                                          bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(),
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return false }
            context.interpolationQuality = .high
            context.clear(CGRect(x: 0, y: 0, width: side, height: side))
            context.draw(image, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        guard drew else { return .empty }

        // Does this image carry a real alpha channel, or is it fully opaque?
        var transparentCount = 0
        for index in stride(from: 3, to: pixels.count, by: 4) where pixels[index] < 250 {
            transparentCount += 1
        }
        let usedAlpha = transparentCount > side * side / 100

        var coverage = [Float](repeating: 0, count: side * side)
        if usedAlpha {
            for i in 0..<(side * side) {
                coverage[i] = Float(pixels[i * 4 + 3]) / 255
            }
        } else {
            var luminance = [Float](repeating: 0, count: side * side)
            for i in 0..<(side * side) {
                let r = Float(pixels[i * 4]) / 255
                let g = Float(pixels[i * 4 + 1]) / 255
                let b = Float(pixels[i * 4 + 2]) / 255
                luminance[i] = 0.2126 * r + 0.7152 * g + 0.0722 * b
            }
            // The corners tell us what the paper is; ink is whatever contrasts with it.
            let corners = [0, side - 1, (side - 1) * side, side * side - 1].map { luminance[$0] }
            let paperIsLight = corners.reduce(0, +) / Float(corners.count) > 0.5
            let threshold = Self.otsuThreshold(luminance)
            for i in 0..<luminance.count {
                let distance = paperIsLight ? (threshold - luminance[i]) : (luminance[i] - threshold)
                // A soft ramp keeps antialiased edges from turning into hard steps.
                coverage[i] = min(max(distance * 4 + 0.5, 0), 1)
            }
        }

        return Silhouette(width: side, height: side, coverage: coverage,
                          inkBounds: inkBounds(coverage, side: side), usedAlpha: usedAlpha)
    }

    /// Otsu's method: the threshold that best separates the histogram into two
    /// classes. Handles logos on off-white or tinted paper.
    private static func otsuThreshold(_ values: [Float]) -> Float {
        var histogram = [Int](repeating: 0, count: 256)
        for value in values {
            histogram[min(max(Int(value * 255), 0), 255)] += 1
        }
        let total = values.count
        var sum: Double = 0
        for i in 0..<256 { sum += Double(i * histogram[i]) }

        var sumBackground: Double = 0
        var weightBackground = 0
        var bestVariance: Double = -1
        var bestThreshold = 128
        for i in 0..<256 {
            weightBackground += histogram[i]
            if weightBackground == 0 { continue }
            let weightForeground = total - weightBackground
            if weightForeground == 0 { break }
            sumBackground += Double(i * histogram[i])
            let meanBackground = sumBackground / Double(weightBackground)
            let meanForeground = (sum - sumBackground) / Double(weightForeground)
            let variance = Double(weightBackground) * Double(weightForeground)
                * (meanBackground - meanForeground) * (meanBackground - meanForeground)
            if variance > bestVariance {
                bestVariance = variance
                bestThreshold = i
            }
        }
        return Float(bestThreshold) / 255
    }

    /// Tight box around everything with meaningful ink, in normalised coordinates.
    private static func inkBounds(_ coverage: [Float], side: Int) -> CGRect {
        var minX = side, minY = side, maxX = -1, maxY = -1
        for y in 0..<side {
            for x in 0..<side where coverage[y * side + x] > 0.5 {
                minX = min(minX, x); maxX = max(maxX, x)
                minY = min(minY, y); maxY = max(maxY, y)
            }
        }
        guard maxX >= minX, maxY >= minY else {
            return CGRect(x: 0, y: 0, width: 1, height: 1)
        }
        let scale = 1.0 / Double(side - 1)
        return CGRect(x: Double(minX) * scale, y: Double(minY) * scale,
                      width: Double(maxX - minX) * scale, height: Double(maxY - minY) * scale)
    }
}
