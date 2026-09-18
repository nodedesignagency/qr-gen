import CoreGraphics
import Foundation

/// How well a piece of artwork will survive being rendered at halftone
/// resolution, and what to tell the user if it will not.
///
/// The thresholds here were calibrated against a spread of test artwork: solid
/// marks, block letters, hairline wordmarks and a detailed illustration. Good
/// marks score above 0.85 on stroke survival; hairline wordmarks and busy
/// illustrations land below 0.25, which is a wide enough gap to act on.
struct SilhouetteAnalysis: Sendable {

    /// Fraction of the frame covered by ink.
    let inkCoverage: Double
    /// Fraction of ink that survives one erosion at halftone resolution. Low
    /// values mean the strokes are about as thin as a single sub-module.
    let strokeSurvival: Double
    /// Transitions per sub-module. High values mean fine detail that the grid
    /// cannot represent.
    let edgeDensity: Double
    /// How much of the histogram sits away from the mid-tones.
    let tonalSeparation: Double

    enum Verdict: Sendable, Equatable {
        case good
        case thinStrokes
        case tooDetailed
        case lowContrast
        case tooSparse
        case tooDense
    }

    var verdict: Verdict {
        if inkCoverage < 0.05 { return .tooSparse }
        if inkCoverage > 0.95 { return .tooDense }
        if strokeSurvival < 0.45 { return .thinStrokes }
        if edgeDensity > 0.12 { return .tooDetailed }
        if tonalSeparation < 0.55 { return .lowContrast }
        return .good
    }

    var isUsable: Bool { verdict == .good }

    /// One-line headline for the warning strip.
    var headline: String {
        switch verdict {
        case .good: return "Silhouette reads cleanly"
        case .thinStrokes: return "Strokes are too thin for this grid"
        case .tooDetailed: return "Too much fine detail to resolve"
        case .lowContrast: return "Low contrast silhouette"
        case .tooSparse: return "Almost no ink in this artwork"
        case .tooDense: return "Artwork is almost solid ink"
        }
    }

    /// Two or three words, for the status chip on the file row.
    var shortStatus: String {
        switch verdict {
        case .good: return "Reads cleanly"
        case .thinStrokes: return "Strokes too thin"
        case .tooDetailed: return "Too detailed"
        case .lowContrast: return "Low contrast"
        case .tooSparse: return "Too little ink"
        case .tooDense: return "Too solid"
        }
    }

    /// What the user can actually do about it.
    var advice: String {
        switch verdict {
        case .good:
            return "Good separation between ink and paper. This will hold its shape."
        case .thinStrokes:
            return "Hairline wordmarks break up at halftone resolution. Try a monogram, an icon, or a heavier weight."
        case .tooDetailed:
            return "Illustrations lose definition when each module is three pixels across. Try a simplified mark."
        case .lowContrast:
            return "Ink and background sit too close in tone to separate reliably. Try a flat, high-contrast version."
        case .tooSparse:
            return "There is very little ink to work with. Crop closer, or use a solid mark."
        case .tooDense:
            return "Nearly the whole frame is ink, so there is no silhouette to read. Try a knocked-out version."
        }
    }

    /// Analyses the ink map at the resolution the symbol will actually use, since
    /// that is where detail is lost.
    static func analyse(_ silhouette: Silhouette, moduleCount: Int, subdivision: Int) -> SilhouetteAnalysis {
        let grid = max(moduleCount * subdivision, 24)
        var ink = [Bool](repeating: false, count: grid * grid)
        var inkCount = 0
        for y in 0..<grid {
            for x in 0..<grid {
                let value = silhouette.sampleFitted(u: (Double(x) + 0.5) / Double(grid),
                                                    v: (Double(y) + 0.5) / Double(grid))
                let isInk = value >= 0.5
                ink[y * grid + x] = isInk
                if isInk { inkCount += 1 }
            }
        }
        let coverage = Double(inkCount) / Double(grid * grid)

        // Erode by one cell: ink that has an unlit orthogonal neighbour is edge,
        // and artwork made entirely of edge has no body to it.
        var survivors = 0
        for y in 0..<grid {
            for x in 0..<grid where ink[y * grid + x] {
                let up = y > 0 && ink[(y - 1) * grid + x]
                let down = y < grid - 1 && ink[(y + 1) * grid + x]
                let left = x > 0 && ink[y * grid + x - 1]
                let right = x < grid - 1 && ink[y * grid + x + 1]
                if up && down && left && right { survivors += 1 }
            }
        }
        let survival = inkCount > 0 ? Double(survivors) / Double(inkCount) : 0

        var transitions = 0
        for y in 0..<grid {
            for x in 1..<grid where ink[y * grid + x] != ink[y * grid + x - 1] { transitions += 1 }
        }
        for x in 0..<grid {
            for y in 1..<grid where ink[y * grid + x] != ink[(y - 1) * grid + x] { transitions += 1 }
        }
        let edges = Double(transitions) / Double(2 * grid * (grid - 1))

        var histogram = [Int](repeating: 0, count: 32)
        for value in silhouette.coverage {
            histogram[min(max(Int(value * 31), 0), 31)] += 1
        }
        let total = max(silhouette.coverage.count, 1)
        let extremes = histogram[0..<8].reduce(0, +) + histogram[24..<32].reduce(0, +)
        let separation = Double(extremes) / Double(total)

        return SilhouetteAnalysis(inkCoverage: coverage, strokeSurvival: survival,
                                  edgeDensity: edges, tonalSeparation: separation)
    }
}
