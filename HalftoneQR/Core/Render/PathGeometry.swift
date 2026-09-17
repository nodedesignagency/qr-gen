import CoreGraphics
import Foundation

/// A device-independent path instruction.
///
/// Both the Core Graphics renderers and the SVG writer build from these, so a
/// PNG, a PDF and an SVG of the same plan are the same geometry rather than
/// three lookalike implementations.
enum PathCommand: Sendable {
    case move(CGPoint)
    case line(CGPoint)
    case curve(control1: CGPoint, control2: CGPoint, end: CGPoint)
    case close
}

enum PathGeometry {

    /// Circular-arc approximation constant for a quarter turn.
    private static let kappa = 0.5522847498307936

    static func commands(for primitive: Primitive) -> [PathCommand] {
        switch primitive {
        case .rect(let rect):
            return rectangle(rect)
        case .roundedRect(let rect, let radius):
            return roundedRectangle(rect, radius: radius)
        case .ellipse(let rect):
            return ellipse(rect)
        case .polygon(let points):
            guard let first = points.first else { return [] }
            return [.move(first)] + points.dropFirst().map { PathCommand.line($0) } + [.close]
        case .ring(let outer, let inner, let outerRadius, let innerRadius):
            return roundedRectangle(outer, radius: outerRadius)
                + roundedRectangle(inner, radius: innerRadius)
        }
    }

    /// Ring primitives carve a hole, so they need the even-odd rule.
    static func usesEvenOdd(_ primitive: Primitive) -> Bool {
        if case .ring = primitive { return true }
        return false
    }

    private static func rectangle(_ r: CGRect) -> [PathCommand] {
        [.move(CGPoint(x: r.minX, y: r.minY)),
         .line(CGPoint(x: r.maxX, y: r.minY)),
         .line(CGPoint(x: r.maxX, y: r.maxY)),
         .line(CGPoint(x: r.minX, y: r.maxY)),
         .close]
    }

    private static func roundedRectangle(_ r: CGRect, radius: Double) -> [PathCommand] {
        let limit = min(r.width, r.height) / 2
        let radius = min(max(radius, 0), limit)
        guard radius > 0.0001 else { return rectangle(r) }
        let offset = radius * kappa
        return [
            .move(CGPoint(x: r.minX + radius, y: r.minY)),
            .line(CGPoint(x: r.maxX - radius, y: r.minY)),
            .curve(control1: CGPoint(x: r.maxX - radius + offset, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: r.minY + radius - offset),
                   end: CGPoint(x: r.maxX, y: r.minY + radius)),
            .line(CGPoint(x: r.maxX, y: r.maxY - radius)),
            .curve(control1: CGPoint(x: r.maxX, y: r.maxY - radius + offset),
                   control2: CGPoint(x: r.maxX - radius + offset, y: r.maxY),
                   end: CGPoint(x: r.maxX - radius, y: r.maxY)),
            .line(CGPoint(x: r.minX + radius, y: r.maxY)),
            .curve(control1: CGPoint(x: r.minX + radius - offset, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: r.maxY - radius + offset),
                   end: CGPoint(x: r.minX, y: r.maxY - radius)),
            .line(CGPoint(x: r.minX, y: r.minY + radius)),
            .curve(control1: CGPoint(x: r.minX, y: r.minY + radius - offset),
                   control2: CGPoint(x: r.minX + radius - offset, y: r.minY),
                   end: CGPoint(x: r.minX + radius, y: r.minY)),
            .close,
        ]
    }

    private static func ellipse(_ r: CGRect) -> [PathCommand] {
        let rx = r.width / 2, ry = r.height / 2
        let ox = rx * kappa, oy = ry * kappa
        let cx = r.midX, cy = r.midY
        return [
            .move(CGPoint(x: cx, y: r.minY)),
            .curve(control1: CGPoint(x: cx + ox, y: r.minY),
                   control2: CGPoint(x: r.maxX, y: cy - oy),
                   end: CGPoint(x: r.maxX, y: cy)),
            .curve(control1: CGPoint(x: r.maxX, y: cy + oy),
                   control2: CGPoint(x: cx + ox, y: r.maxY),
                   end: CGPoint(x: cx, y: r.maxY)),
            .curve(control1: CGPoint(x: cx - ox, y: r.maxY),
                   control2: CGPoint(x: r.minX, y: cy + oy),
                   end: CGPoint(x: r.minX, y: cy)),
            .curve(control1: CGPoint(x: r.minX, y: cy - oy),
                   control2: CGPoint(x: cx - ox, y: r.minY),
                   end: CGPoint(x: cx, y: r.minY)),
            .close,
        ]
    }

    /// Builds a Core Graphics path from a group of primitives, applying a
    /// transform from module units into the target coordinate space.
    static func cgPath(for primitives: [Primitive], transform: CGAffineTransform) -> CGPath {
        let path = CGMutablePath()
        for primitive in primitives {
            for command in commands(for: primitive) {
                switch command {
                case .move(let p):
                    path.move(to: p.applying(transform))
                case .line(let p):
                    path.addLine(to: p.applying(transform))
                case .curve(let c1, let c2, let end):
                    path.addCurve(to: end.applying(transform),
                                  control1: c1.applying(transform),
                                  control2: c2.applying(transform))
                case .close:
                    path.closeSubpath()
                }
            }
        }
        return path
    }

    /// Builds SVG path data from the same commands.
    static func svgPathData(for primitives: [Primitive], scale: Double) -> String {
        var parts: [String] = []
        parts.reserveCapacity(primitives.count * 6)
        func format(_ value: Double) -> String {
            let scaled = value * scale
            // Three decimals is well under a device pixel at any sane export size.
            return String(format: "%.3f", scaled)
                .replacingOccurrences(of: #"\.?0+$"#, with: "", options: .regularExpression)
        }
        for primitive in primitives {
            for command in commands(for: primitive) {
                switch command {
                case .move(let p):
                    parts.append("M\(format(p.x)) \(format(p.y))")
                case .line(let p):
                    parts.append("L\(format(p.x)) \(format(p.y))")
                case .curve(let c1, let c2, let end):
                    parts.append("C\(format(c1.x)) \(format(c1.y)) \(format(c2.x)) \(format(c2.y)) \(format(end.x)) \(format(end.y))")
                case .close:
                    parts.append("Z")
                }
            }
        }
        return parts.joined(separator: " ")
    }
}
