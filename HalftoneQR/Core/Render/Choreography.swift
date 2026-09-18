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
    /// Everything starts at the centre. Through the first fifth of the sequence
    /// it is thrown outward into a cloud of tiny particles — each along its own
    /// line from the centre, to somewhere short of or past where it belongs,
    /// with scatter, so the cloud is a cloud and not a shrunken symbol. The
    /// cloud keeps creeping outward until each particle turns for home, which
    /// it does from the centre out: the symbol crystallises. Every path in is
    /// curved, every curve is continuous, and each particle grows to its full
    /// size with a soft overshoot as it arrives. Nothing steps.
    ///
    /// The finders are particles too: each is broken into tiny tiles sampled
    /// from inside its real rounded shape, which fly in together and last. Once
    /// they are home the crisp finder is laid over them, and because every tile
    /// sits inside the shape, nothing shows past its edge.
    ///
    /// At `time >= 1` this is the plan itself, so an animation ends on exactly
    /// the artwork the still export produces.
    func bigBang(at time: Double) -> RenderPlan {
        let t = min(max(time, 0), 1)
        guard t < 1 else { return self }

        let centre = canvasUnits / 2
        let bang = 0.20          // share of the sequence spent flying outward
        let flight = 0.45        // how long a particle takes to come home
        let finderStart = 0.53   // the eyes turn for home last, together
        let particle = 0.22      // size in flight, as a share of the cell
        let halfDiagonal = Double(moduleCount) / 2 * 1.41421356

        func hash(_ x: Double, _ y: Double, _ salt: Double) -> Double {
            let value = sin(x * 12.9898 + y * 78.233 + salt * 37.719) * 43758.5453
            return value - value.rounded(.down)
        }
        func easeOut(_ x: Double) -> Double { 1 - pow(1 - x, 3) }
        func easeInOut(_ x: Double) -> Double { x * x * (3 - 2 * x) }

        /// Where something that belongs at `home` is now, how big it is, and how
        /// far through its journey home it is. `key` seeds its scatter; `start`
        /// is when it turns for home.
        func place(home: CGPoint, key: CGPoint, start: Double) -> (position: CGPoint, scale: Double, progress: Double) {
            let reach = 0.35 + 0.70 * hash(key.x, key.y, 1)
            let spread = canvasUnits * 0.12
            let far = CGPoint(x: centre + (home.x - centre) * reach + (hash(key.x, key.y, 2) - 0.5) * spread,
                              y: centre + (home.y - centre) * reach + (hash(key.x, key.y, 3) - 0.5) * spread)
            if t < bang {
                let u = easeOut(t / bang)
                return (CGPoint(x: centre + (far.x - centre) * u, y: centre + (far.y - centre) * u),
                        particle * u, 0)
            }
            // The cloud creeps outward until this particle turns for home.
            let creep = 1 + 0.10 * min((min(t, start) - bang) / 0.4, 1)
            let drifted = CGPoint(x: centre + (far.x - centre) * creep, y: centre + (far.y - centre) * creep)
            let u = min(max((t - start) / flight, 0), 1)
            let move = easeInOut(u)
            // The way in curves one way or the other, most of all mid-flight, and
            // is straight at both ends so it joins the drift and the landing.
            let twist = (hash(key.x, key.y, 5) < 0.5 ? -0.5 : 0.5) * sin(.pi * move)
            let vx = drifted.x - home.x, vy = drifted.y - home.y
            let rx = vx * cos(twist) - vy * sin(twist)
            let ry = vx * sin(twist) + vy * cos(twist)
            let position = CGPoint(x: home.x + rx * (1 - move), y: home.y + ry * (1 - move))
            // Grows on the way in, with a soft overshoot that is exactly gone at
            // the moment of arrival.
            let overshoot = 0.10 * sin(.pi * max(0, (u - 0.7) / 0.3))
            return (position, particle + (1 - particle) * move + overshoot, u)
        }

        /// A particle's turn for home, from the centre out with some jitter.
        func start(for home: CGPoint, key: CGPoint) -> Double {
            let radius = min(hypot(home.x - centre, home.y - centre) / halfDiagonal, 1)
            return bang + 0.06 + 0.30 * (0.7 * radius + 0.3 * hash(key.x, key.y, 4))
        }

        var moved: [Cell] = []
        moved.reserveCapacity(cells.count + finders.count * 600)
        for cell in cells {
            let module = CGPoint(x: (cell.centre.x - quietZone).rounded(.down) + 0.5,
                                 y: (cell.centre.y - quietZone).rounded(.down) + 0.5)
            // A module's cells turn for home together, so the light centres they
            // carve out arrive with them.
            let placed = place(home: cell.centre, key: cell.centre, start: start(for: module, key: module))
            // A knocked-out centre is paper on paper: it means nothing in flight
            // and arrives with the module it belongs to.
            if cell.role == .dataKnockout && placed.progress < 0.9 { continue }
            guard placed.scale > 0.01 else { continue }
            var next = cell
            next.centre = placed.position
            next.size = cell.size * placed.scale
            moved.append(next)
        }

        // The eyes: tiles until they are home, then themselves.
        let eyesHome = t >= finderStart + flight
        if !eyesHome {
            for finder in finders {
                for tile in Self.finderTiles(finder) {
                    let placed = place(home: tile.centre, key: tile.centre, start: finderStart)
                    guard placed.scale > 0.01 else { continue }
                    var next = tile
                    next.centre = placed.position
                    next.size = tile.size * placed.scale
                    moved.append(next)
                }
            }
        }

        return RenderPlan(moduleCount: moduleCount, quietZone: quietZone, subdivision: subdivision,
                          palette: palette, paperCornerRadius: paperCornerRadius,
                          cells: moved, finders: eyesHome ? finders : [],
                          emblem: t > 0.95 ? emblem : nil,
                          moduleGrid: moduleGrid, functionGrid: functionGrid,
                          payload: payload, version: version, mask: mask, correction: correction)
    }

    /// A finder broken into tiny square tiles, every one of them wholly inside
    /// the finder's real shape — its rounded ring and its pupil — so the crisp
    /// finder can be laid over the assembled tiles with nothing showing past
    /// its edge.
    private static func finderTiles(_ finder: Finder) -> [Cell] {
        let tile = 0.25
        let outer = CGRect(x: finder.origin.x, y: finder.origin.y, width: 7, height: 7)
        let inner = outer.insetBy(dx: 1, dy: 1)
        let pupil = outer.insetBy(dx: 2, dy: 2)
        let radii: (outer: Double, inner: Double, pupil: Double)
        switch finder.style {
        case .square: radii = (0, 0, 0)
        case .rounded: radii = (2.0, 1.25, 0.9)
        case .circle: radii = (3.5, 2.5, 1.5)
        }

        func inside(_ p: CGPoint, _ rect: CGRect, radius: Double) -> Bool {
            guard rect.contains(p) else { return false }
            let r = min(radius, rect.width / 2, rect.height / 2)
            guard r > 0 else { return true }
            let dx = max(rect.minX + r - p.x, p.x - (rect.maxX - r), 0)
            let dy = max(rect.minY + r - p.y, p.y - (rect.maxY - r), 0)
            return dx * dx + dy * dy <= r * r
        }
        func inShape(_ p: CGPoint) -> Bool {
            (inside(p, outer, radius: radii.outer) && !inside(p, inner, radius: radii.inner))
                || inside(p, pupil, radius: radii.pupil)
        }

        let across = Int((7 / tile).rounded())
        var tiles: [Cell] = []
        tiles.reserveCapacity(across * across)
        for row in 0..<across {
            for column in 0..<across {
                let cx = outer.minX + (Double(column) + 0.5) * tile
                let cy = outer.minY + (Double(row) + 0.5) * tile
                let h = tile / 2
                let corners = [CGPoint(x: cx - h, y: cy - h), CGPoint(x: cx + h, y: cy - h),
                               CGPoint(x: cx - h, y: cy + h), CGPoint(x: cx + h, y: cy + h)]
                guard corners.allSatisfy(inShape) else { continue }
                tiles.append(Cell(centre: CGPoint(x: cx, y: cy), size: tile, shape: .square, role: .structure))
            }
        }
        return tiles
    }
}
