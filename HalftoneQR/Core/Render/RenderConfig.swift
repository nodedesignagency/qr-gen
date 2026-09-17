import Foundation

/// Every knob the halftone renderer reads.
///
/// Only `logoStrength` and `cellShape` are exposed in the UI. The rest are
/// either derived from the artwork or moved automatically by the verify loop.
struct RenderConfig: Sendable, Equatable {

    /// How much of each module is surrendered to the artwork, 0...1.
    ///
    /// At 0 every sub-module matches its module and the result is an ordinary QR
    /// code. At 1 only the sampled centre is held and the other eight cells are
    /// free. The default sits where a wide spread of test artwork still decoded
    /// under heavy blur and at three pixels per module.
    var logoStrength: Double = 0.68

    /// Side of the data-carrying centre cell as a fraction of a module.
    ///
    /// This is the single most effective robustness lever. Measured against a
    /// real decoder, growing the centre from a third of a module to a little over
    /// half took a strength-0.6 render from 23/35 successful captures to 35/35,
    /// at a much smaller cost in likeness than lowering the strength would be.
    var centreFraction: Double = 0.56

    var cellShape: CellShape = .square
    var finderStyle: FinderStyle = .rounded

    /// Gap between adjacent art cells, as a fraction of a cell.
    var cellGap: Double = 0.0

    /// Quiet zone in modules. Four is the minimum the standard allows.
    var quietZone: Double = 4
    /// Corner radius of the paper field, in modules.
    var paperCornerRadius: Double = 3.5

    /// Extra forced agreement for modules sitting next to a function pattern,
    /// where a decoder's grid estimate is most fragile.
    var reinforcementRadius: Int = 2
    var reinforcementAmount: Int = 2

    var correction: QRErrorCorrection = .high

    /// Draw the mark in the middle of the symbol as a knocked-out emblem.
    var showsEmblem: Bool = false

    /// Blend a little of the artwork's greyscale into the threshold so
    /// photographic sources keep their tonality instead of going flat.
    var usesDither: Bool = false

    /// Steps the verify loop walks when a render fails to decode. Each one trades
    /// likeness for robustness, ending at a plain QR code that cannot fail.
    static func fallbackLadder(from config: RenderConfig) -> [RenderConfig] {
        let steps: [(strength: Double, centre: Double)] = [
            (0.78, 0.04),
            (0.55, 0.08),
            (0.32, 0.12),
            (0.00, 0.14),
        ]
        return steps.map { step in
            var next = config
            next.logoStrength = config.logoStrength * step.strength
            next.centreFraction = min(config.centreFraction + step.centre, 0.72)
            return next
        }
    }
}
