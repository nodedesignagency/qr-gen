import CoreGraphics
import Foundation

/// The order modules resolve in, and how.
///
/// Motion here is mechanical on purpose: modules snap into place in quantised
/// steps with a small overshoot, rather than fading. Nothing ever changes
/// opacity — a module is either not placed yet or it is landing.
enum Choreography: String, CaseIterable, Sendable, Identifiable {
    case scanline, radial, diagonal, spiral, develop, structureFirst

    var id: String { rawValue }

    var title: String {
        switch self {
        case .scanline: return "Scanline"
        case .radial: return "Bloom"
        case .diagonal: return "Wipe"
        case .spiral: return "Spiral"
        case .develop: return "Develop"
        case .structureFirst: return "Structure"
        }
    }

    var detail: String {
        switch self {
        case .scanline: return "Top to bottom, one row at a time"
        case .radial: return "Outward from the centre"
        case .diagonal: return "Corner to corner"
        case .spiral: return "Winding in from the edge"
        case .develop: return "Scattered, settling into order"
        case .structureFirst: return "Finders, then timing, then data"
        }
    }

    /// When a module starts landing, 0...1 across the sequence.
    func delay(x: Int, y: Int, count: Int, isFunction: Bool) -> Double {
        let n = Double(max(count - 1, 1))
        let u = Double(x) / n, v = Double(y) / n
        switch self {
        case .scanline:
            return v
        case .radial:
            let dx = u - 0.5, dy = v - 0.5
            return min(sqrt(dx * dx + dy * dy) / 0.7071, 1)
        case .diagonal:
            return (u + v) / 2
        case .spiral:
            let dx = u - 0.5, dy = v - 0.5
            let radius = min(sqrt(dx * dx + dy * dy) / 0.7071, 1)
            let angle = (atan2(dy, dx) + .pi) / (2 * .pi)
            return min(max(radius * 0.65 + angle * 0.35, 0), 1)
        case .develop:
            // A hash, so the scatter is fixed for a given symbol rather than
            // reshuffling on every frame.
            let hash = sin(Double(x) * 12.9898 + Double(y) * 78.233) * 43758.5453
            return hash - hash.rounded(.down)
        case .structureFirst:
            if isFunction { return Double(x + y) / (2 * n) * 0.3 }
            let dx = u - 0.5, dy = v - 0.5
            return 0.34 + min(sqrt(dx * dx + dy * dy) / 0.7071, 1) * 0.66
        }
    }

    /// How long a single module takes to land, as a share of the whole sequence.
    var landingWindow: Double { self == .develop ? 0.16 : 0.22 }
}

extension RenderPlan {

    /// A copy of this plan part-way through its resolve animation.
    ///
    /// Cells that have not started are dropped; cells in flight are scaled. The
    /// geometry is otherwise untouched, so an exported animation ends on exactly
    /// the same artwork the still export produces.
    func revealed(by choreography: Choreography, at time: Double) -> RenderPlan {
        let clamped = min(max(time, 0), 1)
        guard clamped < 1 else { return self }
        let window = choreography.landingWindow
        let span = 1 - window

        func progress(atX x: Int, y: Int, isFunction: Bool) -> Double {
            let delay = choreography.delay(x: x, y: y, count: moduleCount, isFunction: isFunction) * span
            return min(max((clamped - delay) / window, 0), 1)
        }

        /// Quantised overshoot: four discrete steps up to 1.12, then a snap back.
        func landing(_ p: Double) -> Double {
            guard p > 0 else { return 0 }
            guard p < 1 else { return 1 }
            let stepped = (p * 4).rounded(.down) / 4
            return stepped < 0.75 ? stepped * 1.12 : 1.12 - (stepped - 0.75) * 0.48
        }

        var moved: [Cell] = []
        moved.reserveCapacity(cells.count)
        for cell in cells {
            let mx = Int(cell.centre.x - quietZone)
            let my = Int(cell.centre.y - quietZone)
            guard mx >= 0, mx < moduleCount, my >= 0, my < moduleCount else {
                moved.append(cell)
                continue
            }
            let isFunction = functionGrid[my * moduleCount + mx]
            let scale = landing(progress(atX: mx, y: my, isFunction: isFunction))
            guard scale > 0.01 else { continue }
            var next = cell
            next.size = cell.size * scale
            moved.append(next)
        }

        let liveFinders = finders.filter { finder in
            let mx = Int(finder.origin.x - quietZone) + 3
            let my = Int(finder.origin.y - quietZone) + 3
            return progress(atX: mx, y: my, isFunction: true) > 0.35
        }

        return RenderPlan(moduleCount: moduleCount, quietZone: quietZone, subdivision: subdivision,
                          palette: palette, paperCornerRadius: paperCornerRadius,
                          cells: moved, finders: liveFinders,
                          emblem: clamped > 0.92 ? emblem : nil,
                          moduleGrid: moduleGrid, functionGrid: functionGrid,
                          payload: payload, version: version, mask: mask, correction: correction)
    }
}
