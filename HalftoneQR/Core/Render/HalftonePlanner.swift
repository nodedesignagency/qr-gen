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

        var cells: [RenderPlan.Cell] = []
        cells.reserveCapacity(count * count * 4)

        let cellSize = (1.0 / Double(subdivision)) * (1 - config.cellGap)
        let centreSize = config.centreFraction

        for my in 0..<count {
            for mx in 0..<count {
                let isDark = symbol.isDark(x: mx, y: my)
                let originX = quiet + Double(mx)
                let originY = quiet + Double(my)

                // The three finder patterns are drawn as whole marks elsewhere.
                if finderRegions.contains(where: { $0.contains(CGPoint(x: Double(mx) + 0.5,
                                                                      y: Double(my) + 0.5)) }) {
                    continue
                }

                if symbol.isFunction(x: mx, y: my) {
                    if isDark {
                        cells.append(RenderPlan.Cell(
                            centre: CGPoint(x: originX + 0.5, y: originY + 0.5),
                            size: 1.0, shape: .square, role: .structure))
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

                for (slot, offset) in neighbourOrder.enumerated() where values[slot] {
                    cells.append(RenderPlan.Cell(
                        centre: CGPoint(x: originX + (Double(offset.x) + 0.5) / Double(subdivision),
                                        y: originY + (Double(offset.y) + 0.5) / Double(subdivision)),
                        size: cellSize, shape: config.cellShape, role: .art))
                }

                // The sampled centre goes on last and is never negotiable.
                cells.append(RenderPlan.Cell(
                    centre: CGPoint(x: originX + 0.5, y: originY + 0.5),
                    size: centreSize,
                    shape: config.cellShape == .diamond ? .square : config.cellShape,
                    role: isDark ? .data : .dataKnockout))
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
