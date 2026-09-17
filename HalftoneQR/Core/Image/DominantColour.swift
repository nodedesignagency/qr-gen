import CoreGraphics
import Foundation
import SwiftUI

/// Pulls a usable brand colour out of a piece of artwork.
///
/// "Dominant" on its own tends to return the background, or a muddy average of
/// an antialiased edge. This weights each bucket by how much colour it actually
/// carries, so a small saturated mark beats a large grey field.
enum DominantColour {

    /// A hue-bucketed histogram vote, then a refinement pass over the winning
    /// bucket's true pixels.
    static func extract(from image: CGImage) -> RGB? {
        let side = 64
        var pixels = [UInt8](repeating: 0, count: side * side * 4)
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
        guard drew else { return nil }

        // 12 hues x 3 saturation bands x 3 value bands, plus a neutral bucket.
        var votes = [Int: Double]()
        var sums = [Int: (r: Double, g: Double, b: Double, n: Double)]()
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.4 else { continue }
            let r = Double(pixels[index]) / 255
            let g = Double(pixels[index + 1]) / 255
            let b = Double(pixels[index + 2]) / 255
            let hsv = RGB(red: r, green: g, blue: b).hsv

            // Near-white is almost always paper; near-black is usually ink we can
            // still use, but it should not outvote real colour.
            if hsv.value > 0.93 && hsv.saturation < 0.12 { continue }
            let weight = alpha * (0.25 + hsv.saturation * 1.75)

            let key: Int
            if hsv.saturation < 0.15 {
                key = -1 - Int(hsv.value * 2.99)  // neutral buckets by lightness
            } else {
                let hue = Int(hsv.hue / 30) % 12
                key = hue * 9 + Int(hsv.saturation * 2.99) * 3 + Int(hsv.value * 2.99)
            }
            votes[key, default: 0] += weight
            var bucket = sums[key] ?? (0, 0, 0, 0)
            bucket.r += r * weight; bucket.g += g * weight; bucket.b += b * weight
            bucket.n += weight
            sums[key] = bucket
        }

        guard let winner = votes.max(by: { $0.value < $1.value })?.key,
              let bucket = sums[winner], bucket.n > 0
        else { return nil }
        return RGB(red: bucket.r / bucket.n, green: bucket.g / bucket.n, blue: bucket.b / bucket.n)
    }

    /// Nudges a colour until it has enough contrast against the light field a QR
    /// symbol needs, without losing its identity.
    ///
    /// A pale yellow logo would make an unreadable symbol, so it gets darkened
    /// until the contrast ratio clears the threshold. Hue and saturation are
    /// preserved; only lightness moves.
    static func readableInk(_ colour: RGB, onPaper paper: RGB, minimumRatio: Double = 5.0) -> RGB {
        var candidate = colour
        var steps = 0
        let paperIsLight = paper.relativeLuminance > 0.5
        while candidate.contrastRatio(against: paper) < minimumRatio && steps < 40 {
            var hsv = candidate.hsv
            hsv.value = paperIsLight ? max(hsv.value - 0.03, 0) : min(hsv.value + 0.03, 1)
            // Deep shades drift grey unless saturation is held up.
            hsv.saturation = min(hsv.saturation * 1.01, 1)
            candidate = RGB(hsv: hsv)
            steps += 1
        }
        return candidate
    }
}

/// A plain linear-free sRGB triple. Value type so it can cross actor boundaries.
struct RGB: Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    static let ink = RGB(red: 0.055, green: 0.055, blue: 0.067)
    static let paper = RGB(red: 1, green: 1, blue: 1)

    var relativeLuminance: Double {
        func channel(_ value: Double) -> Double {
            value <= 0.03928 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * channel(red) + 0.7152 * channel(green) + 0.0722 * channel(blue)
    }

    func contrastRatio(against other: RGB) -> Double {
        let a = relativeLuminance, b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }

    var hsv: HSV {
        let maxValue = max(red, green, blue)
        let minValue = min(red, green, blue)
        let delta = maxValue - minValue
        var hue: Double = 0
        if delta > 0 {
            if maxValue == red {
                hue = 60 * (((green - blue) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxValue == green {
                hue = 60 * ((blue - red) / delta + 2)
            } else {
                hue = 60 * ((red - green) / delta + 4)
            }
        }
        if hue < 0 { hue += 360 }
        return HSV(hue: hue, saturation: maxValue == 0 ? 0 : delta / maxValue, value: maxValue)
    }

    init(red: Double, green: Double, blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    init(hsv: HSV) {
        let c = hsv.value * hsv.saturation
        let x = c * (1 - abs((hsv.hue / 60).truncatingRemainder(dividingBy: 2) - 1))
        let m = hsv.value - c
        let (r, g, b): (Double, Double, Double)
        switch hsv.hue {
        case ..<60: (r, g, b) = (c, x, 0)
        case ..<120: (r, g, b) = (x, c, 0)
        case ..<180: (r, g, b) = (0, c, x)
        case ..<240: (r, g, b) = (0, x, c)
        case ..<300: (r, g, b) = (x, 0, c)
        default: (r, g, b) = (c, 0, x)
        }
        self.init(red: r + m, green: g + m, blue: b + m)
    }

    /// Parses `#rgb`, `#rrggbb` or `#rrggbbaa`, which is what `theme-color` uses.
    init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("#") { text.removeFirst() }
        if text.count == 3 {
            text = text.map { "\($0)\($0)" }.joined()
        }
        guard text.count == 6 || text.count == 8, let value = UInt32(text.prefix(6), radix: 16) else {
            return nil
        }
        self.init(red: Double((value >> 16) & 0xFF) / 255,
                  green: Double((value >> 8) & 0xFF) / 255,
                  blue: Double(value & 0xFF) / 255)
    }

    var hexString: String {
        String(format: "#%02X%02X%02X",
               Int((red * 255).rounded()), Int((green * 255).rounded()), Int((blue * 255).rounded()))
    }

    var cgColor: CGColor {
        CGColor(red: red, green: green, blue: blue, alpha: 1)
    }

    var swiftUIColor: Color {
        Color(.sRGB, red: red, green: green, blue: blue, opacity: 1)
    }

    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(red: red + (other.red - red) * t,
                   green: green + (other.green - green) * t,
                   blue: blue + (other.blue - blue) * t)
    }
}

struct HSV: Sendable, Equatable, Hashable {
    var hue: Double        // 0..<360
    var saturation: Double // 0...1
    var value: Double      // 0...1
}
