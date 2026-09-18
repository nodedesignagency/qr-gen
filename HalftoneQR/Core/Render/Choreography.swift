import CoreGraphics
import Foundation

/// The order modules resolve in, and how.
///
/// Motion here is mechanical on purpose: modules snap into place in quantised
/// steps with a small overshoot, rather than fading. Nothing ever changes
/// opacity — a module is either not placed yet or it is landing.
///
/// `bigBang` is the one order that moves cells as well as scaling them: see
/// `RenderPlan.bigBang(at:)`.
enum Choreography: String, CaseIterable, Sendable, Identifiable {
    case bigBang, scanline, radial, diagonal, spiral, develop, structureFirst

    var id: String { rawValue }

    /// The orders offered to the user: all of them.
    static var selectable: [Choreography] { allCases }

    var title: String {
        switch self {
        case .bigBang: return "Big bang"
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
        case .bigBang: return "Out from one point, then into place"
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
        case .bigBang:
            // Not used for placement — the big bang keeps its own clock — but
            // spelled out so it has a sensible order wherever one is asked for.
            let hash = sin(Double(x) * 12.9898 + Double(y) * 78.233) * 43758.5453
            return hash - hash.rounded(.down)
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
    var landingWindow: Double {
        switch self {
        case .develop, .bigBang: return 0.16
        default: return 0.22
        }
    }
}

extension RenderPlan {

    /// A copy of this plan part-way through its resolve animation.
    ///
    /// Cells that have not started are dropped; cells in flight are scaled. The
    /// geometry is otherwise untouched, so an exported animation ends on exactly
    /// the same artwork the still export produces.
    func revealed(by choreography: Choreography, at time: Double) -> RenderPlan {
        if choreography == .bigBang { return bigBang(at: time) }
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

extension RenderPlan {

    /// A copy of this plan part-way through the big bang.
    ///
    /// Everything starts at the centre. Through the first part of the sequence
    /// it is thrown outward into a cloud — each cell along its own line from the
    /// centre to a point past where it belongs, with some scatter, so the cloud
    /// is a cloud and not a zoomed symbol. It hangs for a beat. Then, module by
    /// module, the cells fall back in, overshoot, and snap into place. Timing is
    /// per module, so a module's cells arrive together and the light centres
    /// they carve out arrive with them. The finders come in whole, and last.
    ///
    /// Cells are only ever moved and scaled, never faded, and at `time >= 1`
    /// this is the plan itself, so an animation ends on exactly the artwork the
    /// still export produces.
    func bigBang(at time: Double) -> RenderPlan {
        let t = min(max(time, 0), 1)
        guard t < 1 else { return self }

        let centre = canvasUnits / 2
        let bang = 0.22      // share of the sequence spent flying outward
        let flight = 0.42    // how long a cell takes to fall back in

        func hash(_ x: Double, _ y: Double, _ salt: Double) -> Double {
            let value = sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
            return value - value.rounded(.down)
        }
        func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
        func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }

        /// Where something that belongs at `home` is now, how big it is, and
        /// whether it has arrived. `module` sets its timing, `key` its scatter.
        func place(home: CGPoint, module: CGPoint, key: CGPoint,
                   start fixedStart: Double? = nil) -> (position: CGPoint, scale: Double, arrived: Bool) {
            let reach = 1.25 + 0.55 * hash(key.x, key.y, 1)
            let spread = canvasUnits * 0.07
            let far = CGPoint(x: centre + (home.x - centre) * reach + (hash(key.x, key.y, 2) - 0.5) * spread,
                              y: centre + (home.y - centre) * reach + (hash(key.x, key.y, 3) - 0.5) * spread)
            if t < bang {
                let u = easeOut(t / bang)
                return (CGPoint(x: centre + (far.x - centre) * u, y: centre + (far.y - centre) * u),
                        0.55 * u, false)
            }
            let start = fixedStart ?? bang + 0.02 + (1 - bang - flight - 0.02) * hash(module.x, module.y, 4)
            let u = min(max((t - start) / flight, 0), 1)
            let move = easeInOut(min(u / 0.85, 1))
            let position = CGPoint(x: far.x + (home.x - far.x) * move, y: far.y + (home.y - far.y) * move)
            // Grows on the way in, overshoots, and snaps back in one step.
            let scale = u < 0.85 ? 0.55 + 0.57 * move : (u < 0.93 ? 1.12 : 1.0)
            return (position, scale, u >= 0.85)
        }

        var moved: [Cell] = []
        moved.reserveCapacity(cells.count)
        for cell in cells {
            let module = CGPoint(x: (cell.centre.x - quietZone).rounded(.down),
                                 y: (cell.centre.y - quietZone).rounded(.down))
            let placed = place(home: cell.centre, module: module, key: cell.centre)
            // A knocked-out centre is paper on paper: it means nothing in flight
            // and arrives with the module it belongs to.
            if cell.role == .dataKnockout && !placed.arrived { continue }
            guard placed.scale > 0.01 else { continue }
            var next = cell
            next.centre = placed.position
            next.size = cell.size * placed.scale
            moved.append(next)
        }

        let liveFinders: [Finder] = finders.compactMap { finder in
            let home = CGPoint(x: finder.origin.x + 3.5, y: finder.origin.y + 3.5)
            let placed = place(home: home, module: home, key: home, start: 0.56)
            guard placed.scale > 0.01 else { return nil }
            var next = finder
            next.origin = CGPoint(x: placed.position.x - 3.5, y: placed.position.y - 3.5)
            next.scale = placed.scale
            return next
        }

        return RenderPlan(moduleCount: moduleCount, quietZone: quietZone, subdivision: subdivision,
                          palette: palette, paperCornerRadius: paperCornerRadius,
                          cells: moved, finders: liveFinders,
                          emblem: t > 0.92 ? emblem : nil,
                          moduleGrid: moduleGrid, functionGrid: functionGrid,
                          payload: payload, version: version, mask: mask, correction: correction)
    }
}
