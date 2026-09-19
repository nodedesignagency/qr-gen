import CoreGraphics
import Foundation

/// Builds the halftone render plan.
///
/// The technique: every module is subdivided into a 3x3 grid. The centre cell is
/// pinned to the module's true value, because that is the point a decoder
/// samples. The eight cells around it are free to take the artwork's value, so
/// the picture is carried at three times the module resolution while the data
/// stays intact.
///
/// Two things keep it scannable. Function patterns — finders, timing, alignment,
/// format — are always drawn whole; without that, nothing decodes at all. And a
/// number of the free cells, set by `logoStrength`, are forced back to agree with
/// their module, so a blurred camera sample of the module still lands on the
/// right side of the threshold.
enum HalftonePlanner {

    static let subdivision = 3

    /// Sub-cell offsets in the order we are willing to sacrifice them.
    ///
    /// Orthogonal neighbours come first: they sit closest to the sampled centre
    /// and dominate it once the image is blurred, so they buy the most robustness
    /// per cell given up.
    private static let neighbourOrder: [(x: Int, y: Int)] = [
        (1, 0), (0, 1), (2, 1), (1, 2),   // orthogonal
        (0, 0), (2, 0), (0, 2), (2, 2),   // diagonal
    ]

    static func makePlan(payload: String,
                         silhouette: Silhouette?,
                         config: RenderConfig,
                         palette: Palette) throws -> RenderPlan {

        let symbol = try encode(payload: payload, silhouette: silhouette, config: config)
        let count = symbol.size
        let grid = count * subdivision
        let quiet = config.quietZone

        // Resample the artwork once, at exactly the resolution we will consume it.
        var coverage = [Float](repeating: 0, count: grid * grid)
        if let silhouette {
            for y in 0..<grid {
                for x in 0..<grid {
                    coverage[y * grid + x] = silhouette.sampleFitted(
                        u: (Double(x) + 0.5) / Double(grid),
                        v: (Double(y) + 0.5) / Double(grid))
                }
            }
        }

        let reinforced = reinforcementMap(symbol: symbol, radius: config.reinforcementRadius)
        let finderRegions = symbol.finderOrigins.map {
            CGRect(x: Double($0.x), y: Double($0.y), width: 7, height: 7)
        }

        // Pass one: decide every sub-module, into a grid at that resolution.
        // The rounding needs each cell's neighbours across module boundaries,
        // so nothing is drawn until the whole grid is decided.
        enum Kind: UInt8 { case outside, art, structure, centre }
        var kind = [Kind](repeating: .outside, count: grid * grid)
        var dark = [Bool](repeating: false, count: grid * grid)

        for my in 0..<count {
            for mx in 0..<count {
                let isDark = symbol.isDark(x: mx, y: my)

                // The three finder patterns are drawn as whole marks elsewhere.
                if finderRegions.contains(where: { $0.contains(CGPoint(x: Double(mx) + 0.5,
                                                                      y: Double(my) + 0.5)) }) {
                    continue
                }

                if symbol.isFunction(x: mx, y: my) {
                    for oy in 0..<subdivision {
                        for ox in 0..<subdivision {
                            let index = (my * subdivision + oy) * grid + mx * subdivision + ox
                            kind[index] = .structure
                            dark[index] = isDark
                        }
                    }
                    continue
                }

                // How many of the eight free cells must agree with this module.
                let strength = min(max(config.logoStrength, 0), 1)
                var required = Int((1 - strength) * 8 + 0.5)
                if reinforced[my * count + mx] {
                    required = min(8, required + config.reinforcementAmount)
                }

                // Read the artwork, and price up what each cell would cost to override.
                var values = [Bool](repeating: false, count: 8)
                var costs = [(cost: Float, slot: Int)]()
                costs.reserveCapacity(8)
                let target: Float = isDark ? 1 : 0
                for (slot, offset) in neighbourOrder.enumerated() {
                    let sample = coverage[(my * subdivision + offset.y) * grid + mx * subdivision + offset.x]
                    values[slot] = threshold(sample, x: mx * subdivision + offset.x,
                                             y: my * subdivision + offset.y, dither: config.usesDither)
                    costs.append((abs(sample - target), slot))
                }

                // Cells that already agree cost nothing, so they are taken first and
                // the quota is only spent on real overrides when it has to be.
                if required > 0 {
                    costs.sort { $0.cost == $1.cost ? $0.slot < $1.slot : $0.cost < $1.cost }
                    for index in 0..<min(required, 8) {
                        values[costs[index].slot] = isDark
                    }
                }

                for (slot, offset) in neighbourOrder.enumerated() {
                    let index = (my * subdivision + offset.y) * grid + mx * subdivision + offset.x
                    kind[index] = .art
                    dark[index] = values[slot]
                }
                // The sampled centre is drawn as its own, larger cell below; in
                // the grid it is what its neighbours round toward or join.
                let centre = (my * subdivision + 1) * grid + mx * subdivision + 1
                kind[centre] = .centre
                dark[centre] = isDark
            }
        }

        func filled(_ x: Int, _ y: Int) -> Bool {
            guard x >= 0, y >= 0, x < grid, y < grid else { return false }
            let index = y * grid + x
            return kind[index] != .outside && dark[index]
        }

        // Pass two: the cells, each rounded by its neighbours. Runs of square
        // cells are drawn as one shape — a corner is rounded where nothing
        // touches it, and the notch where two cells meet at a corner is filled
        // with a fillet — so the mark reads as a silhouette, not a grid. Dots
        // and diamonds stand on their own.
        var cells: [RenderPlan.Cell] = []
        cells.reserveCapacity(count * count * 6)
        let cellSize = (1.0 / Double(subdivision)) * (1 - config.cellGap)
        let centreSize = config.centreFraction
        let joins = config.cellShape == .square && config.cellGap == 0
        let fillet = cellSize * 0.5

        for fy in 0..<grid {
            for fx in 0..<grid {
                let index = fy * grid + fx
                let role: RenderPlan.Cell.Role
                switch kind[index] {
                case .outside, .centre: continue
                case .art: role = .art
                case .structure: role = .structure
                }
                let x = quiet + (Double(fx) + 0.5) / Double(subdivision)
                let y = quiet + (Double(fy) + 0.5) / Double(subdivision)
                let left = filled(fx - 1, fy), right = filled(fx + 1, fy)
                let up = filled(fx, fy - 1), down = filled(fx, fy + 1)

                if dark[index] {
                    var rounding: RenderPlan.Cell.Rounding = .none
                    if joins {
                        rounding = .convex(topLeft: (!left && !up) ? 0.5 : 0,
                                           topRight: (!right && !up) ? 0.5 : 0,
                                           bottomRight: (!right && !down) ? 0.5 : 0,
                                           bottomLeft: (!left && !down) ? 0.5 : 0)
                    }
                    cells.append(RenderPlan.Cell(centre: CGPoint(x: x, y: y), size: cellSize,
                                                 shape: config.cellShape, role: role, rounding: rounding))
                } else if joins {
                    let half = cellSize / 2, inset = fillet / 2
                    let fillets: [(RenderPlan.Cell.Corner, Bool, CGPoint)] = [
                        (.topLeft, up && left, CGPoint(x: x - half + inset, y: y - half + inset)),
                        (.topRight, up && right, CGPoint(x: x + half - inset, y: y - half + inset)),
                        (.bottomRight, down && right, CGPoint(x: x + half - inset, y: y + half - inset)),
                        (.bottomLeft, down && left, CGPoint(x: x - half + inset, y: y + half - inset)),
                    ]
                    for (corner, needed, centre) in fillets where needed {
                        cells.append(RenderPlan.Cell(centre: centre, size: fillet, shape: .square,
                                                     role: role, rounding: .concave(corner)))
                    }
                }
            }
        }

        // Pass three: the sampled centres. Never negotiable, and drawn as their
        // own cells: a dark one rounded only where nothing dark touches it, a
        // light one — punched out of the artwork — always rounded.
        for my in 0..<count {
            for mx in 0..<count where !symbol.isFunction(x: mx, y: my) {
                let isDark = symbol.isDark(x: mx, y: my)
                let shape: CellShape = config.cellShape == .diamond ? .square : config.cellShape
                var rounding: RenderPlan.Cell.Rounding = .none
                if shape == .square {
                    if isDark {
                        let fx = mx * subdivision + 1, fy = my * subdivision + 1
                        func clear(_ dx: Int, _ dy: Int) -> Bool { !filled(fx + dx, fy + dy) }
                        rounding = .convex(
                            topLeft: (clear(-1, 0) && clear(0, -1) && clear(-1, -1)) ? 0.3 : 0,
                            topRight: (clear(1, 0) && clear(0, -1) && clear(1, -1)) ? 0.3 : 0,
                            bottomRight: (clear(1, 0) && clear(0, 1) && clear(1, 1)) ? 0.3 : 0,
                            bottomLeft: (clear(-1, 0) && clear(0, 1) && clear(-1, 1)) ? 0.3 : 0)
                    } else {
                        rounding = .convex(topLeft: 0.3, topRight: 0.3, bottomRight: 0.3, bottomLeft: 0.3)
                    }
                }
                cells.append(RenderPlan.Cell(
                    centre: CGPoint(x: quiet + Double(mx) + 0.5, y: quiet + Double(my) + 0.5),
                    size: centreSize, shape: shape,
                    role: isDark ? .data : .dataKnockout, rounding: rounding))
            }
        }

        let finders = symbol.finderOrigins.map {
            RenderPlan.Finder(origin: CGPoint(x: quiet + Double($0.x), y: quiet + Double($0.y)),
                              style: config.finderStyle)
        }

        let emblem = config.showsEmblem
            ? makeEmblem(silhouette: silhouette, moduleCount: count, quietZone: quiet)
            : nil

        var moduleGrid = [Bool](repeating: false, count: count * count)
        var functionGrid = [Bool](repeating: false, count: count * count)
        for y in 0..<count {
            for x in 0..<count {
                moduleGrid[y * count + x] = symbol.isDark(x: x, y: y)
                functionGrid[y * count + x] = symbol.isFunction(x: x, y: y)
            }
        }

        return RenderPlan(moduleCount: count,
                          quietZone: quiet,
                          subdivision: subdivision,
                          palette: palette,
                          paperCornerRadius: config.paperCornerRadius,
                          cells: cells,
                          finders: finders,
                          emblem: emblem,
                          moduleGrid: moduleGrid,
                          functionGrid: functionGrid,
                          payload: payload,
                          version: symbol.version,
                          mask: symbol.mask,
                          correction: symbol.correction)
    }

    // MARK: - Encoding

    /// Encodes the payload, letting the artwork pick the data mask when there is
    /// artwork to match. Across the test set this recovered the best available
    /// mask in four cases out of five, worth up to four points of likeness for
    /// no cost in robustness.
    private static func encode(payload: String, silhouette: Silhouette?,
                               config: RenderConfig) throws -> QRSymbol {
        guard let silhouette else {
            return try QREncoder.encode(text: payload, correction: config.correction,
                                        maskChoice: .automatic)
        }
        let choice = QRMaskChoice.matchingArtwork { symbol in
            let count = symbol.size
            var agree = 0, total = 0
            for y in 0..<count {
                for x in 0..<count where !symbol.isFunction(x: x, y: y) {
                    let wanted = silhouette.sampleFitted(u: (Double(x) + 0.5) / Double(count),
                                                         v: (Double(y) + 0.5) / Double(count)) >= 0.5
                    if symbol.isDark(x: x, y: y) == wanted { agree += 1 }
                    total += 1
                }
            }
            return total > 0 ? Double(agree) / Double(total) : 0
        }
        return try QREncoder.encode(text: payload, correction: config.correction, maskChoice: choice)
    }

    // MARK: - Helpers

    /// A 4x4 ordered dither, used only for photographic sources where a hard
    /// threshold would flatten everything into blobs.
    private static let bayer: [Float] = [
         0,  8,  2, 10,
        12,  4, 14,  6,
         3, 11,  1,  9,
        15,  7, 13,  5,
    ].map { Float($0) / 16 }

    private static func threshold(_ value: Float, x: Int, y: Int, dither: Bool) -> Bool {
        guard dither else { return value >= 0.5 }
        return value >= bayer[(y % 4) * 4 + (x % 4)]
    }

    /// Marks the free modules within `radius` of any function pattern. A decoder
    /// locates the sampling grid from those patterns, so the modules touching
    /// them are the ones worth reinforcing.
    private static func reinforcementMap(symbol: QRSymbol, radius: Int) -> [Bool] {
        let count = symbol.size
        var map = [Bool](repeating: false, count: count * count)
        guard radius > 0 else { return map }
        for y in 0..<count {
            for x in 0..<count where !symbol.isFunction(x: x, y: y) {
                var near = false
                search: for dy in -radius...radius {
                    for dx in -radius...radius {
                        if symbol.isFunction(x: x + dx, y: y + dy) { near = true; break search }
                    }
                }
                map[y * count + x] = near
            }
        }
        return map
    }

    /// A small knocked-out mark in the middle of the symbol. Kept under a fifth of
    /// the width so the damage stays well inside what the error correction can
    /// absorb — and the verify pass is the real guarantee.
    private static func makeEmblem(silhouette: Silhouette?, moduleCount: Int,
                                   quietZone: Double) -> RenderPlan.Emblem? {
        guard let silhouette else { return nil }
        let span = Double(moduleCount) * 0.17
        let centre = quietZone + Double(moduleCount) / 2
        let rect = CGRect(x: centre - span / 2, y: centre - span / 2, width: span, height: span)
        let resolution = 11
        let cell = span * 0.72 / Double(resolution)
        var marks: [Primitive] = []
        for y in 0..<resolution {
            for x in 0..<resolution {
                let u = (Double(x) + 0.5) / Double(resolution)
                let v = (Double(y) + 0.5) / Double(resolution)
                guard silhouette.sampleFitted(u: u, v: v, padding: 0.02) >= 0.5 else { continue }
                let px = rect.minX + span * 0.14 + (Double(x) + 0.5) * (span * 0.72 / Double(resolution))
                let py = rect.minY + span * 0.14 + (Double(y) + 0.5) * (span * 0.72 / Double(resolution))
                marks.append(.rect(CGRect(x: px - cell / 2, y: py - cell / 2,
                                          width: cell, height: cell)))
            }
        }
        guard !marks.isEmpty else { return nil }
        return RenderPlan.Emblem(rect: rect, cornerRadius: span * 0.22, marks: marks)
    }
}
