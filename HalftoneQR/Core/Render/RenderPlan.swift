import CoreGraphics
import Foundation

/// The shape a single sub-module is drawn with.
enum CellShape: String, CaseIterable, Sendable, Identifiable {
    case square, dot, diamond

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: return "Square"
        case .dot: return "Dot"
        case .diamond: return "Diamond"
        }
    }
}

/// How the three corner finder patterns are drawn.
enum FinderStyle: String, CaseIterable, Sendable, Identifiable {
    case square, rounded, circle

    var id: String { rawValue }

    var label: String {
        switch self {
        case .square: return "Square"
        case .rounded: return "Rounded"
        case .circle: return "Circle"
        }
    }
}

/// A resolution-independent drawing instruction.
///
/// Everything the app exports — bitmap, PDF and SVG — is built from this one
/// list, so the three formats cannot drift apart.
enum Primitive: Sendable {
    case rect(CGRect)
    case roundedRect(CGRect, radius: Double)
    case ellipse(CGRect)
    case polygon([CGPoint])
    /// Outer shape with a hole in it, filled even-odd.
    case ring(outer: CGRect, inner: CGRect, outerRadius: Double, innerRadius: Double)
}

/// The colours a plan is drawn with. Varying only this produces the export
/// variants without re-planning the symbol.
struct Palette: Sendable, Equatable {
    var paper: RGB
    /// Data-carrying centre cells.
    var ink: RGB
    /// Finder patterns, timing and alignment.
    var structure: RGB
    /// The cells that carry the artwork.
    var art: RGB

    static func monochrome(paper: RGB = .paper, ink: RGB = .ink) -> Palette {
        Palette(paper: paper, ink: ink, structure: ink, art: ink)
    }
}

/// Everything needed to draw one symbol at any size.
///
/// Coordinates are in module units with the origin at the top-left of the quiet
/// zone, so a renderer only has to scale by `pixelSize / canvasUnits`.
struct RenderPlan: Sendable, Identifiable {

    /// Assigned on creation so views can key their caches off a plan without
    /// having to make the whole structure equatable.
    let id = UUID()

    let moduleCount: Int
    let quietZone: Double
    let subdivision: Int
    var palette: Palette
    /// Corner radius of the paper field, in module units.
    let paperCornerRadius: Double
    let cells: [Cell]
    let finders: [Finder]
    let emblem: Emblem?
    /// Module-resolution copy of the symbol, used by the resolve animation.
    let moduleGrid: [Bool]
    let functionGrid: [Bool]
    /// Carried through for the verify screen and the export filename.
    let payload: String
    let version: Int
    let mask: Int
    let correction: QRErrorCorrection

    var canvasUnits: Double { Double(moduleCount) + quietZone * 2 }

    struct Cell: Sendable {
        /// Centre of the cell, in module units.
        var centre: CGPoint
        /// Side length, in module units.
        var size: Double
        var shape: CellShape
        var role: Role

        enum Role: UInt8, Sendable {
            /// A free sub-module carrying the artwork.
            case art
            /// A function module — timing, alignment or format — drawn whole.
            case structure
            /// The dark sub-module a decoder samples. Never compromised.
            case data
            /// The light sub-module a decoder samples, punched back out of the
            /// artwork so a light module reads as light.
            case dataKnockout
        }
    }

    struct Finder: Sendable {
        /// Top-left of the 7x7 pattern, in module units.
        var origin: CGPoint
        var style: FinderStyle
        /// Drawn this much larger or smaller about its centre. 1 at rest; the
        /// resolve animations bring the finders in through it.
        var scale: Double = 1
    }

    struct Emblem: Sendable {
        var rect: CGRect
        var cornerRadius: Double
        /// Cells of the logo mark drawn inside the knockout.
        var marks: [Primitive]
    }
}

/// Turns a plan into flat, colour-grouped geometry.
enum PlanFlattener {

    struct Group: Sendable {
        var colour: RGB
        var primitives: [Primitive]
    }

    /// Order matters: paper first, then art, then structure, then the data cells
    /// on top so nothing can cover the modules a decoder samples.
    static func flatten(_ plan: RenderPlan) -> [Group] {
        var art: [Primitive] = []
        var structure: [Primitive] = []
        var data: [Primitive] = []
        var knockout: [Primitive] = []
        art.reserveCapacity(plan.cells.count)

        for cell in plan.cells {
            let primitive = primitive(for: cell)
            switch cell.role {
            case .art: art.append(primitive)
            case .structure: structure.append(primitive)
            case .data: data.append(primitive)
            case .dataKnockout: knockout.append(primitive)
            }
        }
        for finder in plan.finders {
            structure.append(contentsOf: primitives(for: finder))
        }

        // Paper, then artwork, then structure, and the sampled centres last so
        // nothing can ever paint over the modules a decoder reads.
        var groups: [Group] = [
            Group(colour: plan.palette.paper, primitives: [
                .roundedRect(CGRect(x: 0, y: 0, width: plan.canvasUnits, height: plan.canvasUnits),
                             radius: plan.paperCornerRadius)
            ]),
            Group(colour: plan.palette.art, primitives: art),
            Group(colour: plan.palette.structure, primitives: structure),
            Group(colour: plan.palette.paper, primitives: knockout),
            Group(colour: plan.palette.ink, primitives: data),
        ]

        if let emblem = plan.emblem {
            groups.append(Group(colour: plan.palette.paper, primitives: [
                .roundedRect(emblem.rect, radius: emblem.cornerRadius)
            ]))
            groups.append(Group(colour: plan.palette.structure, primitives: emblem.marks))
        }
        return groups.filter { !$0.primitives.isEmpty }
    }

    static func primitive(for cell: RenderPlan.Cell) -> Primitive {
        let half = cell.size / 2
        let box = CGRect(x: cell.centre.x - half, y: cell.centre.y - half,
                         width: cell.size, height: cell.size)
        switch cell.shape {
        case .square:
            return .rect(box)
        case .dot:
            return .ellipse(box)
        case .diamond:
            return .polygon([
                CGPoint(x: box.midX, y: box.minY),
                CGPoint(x: box.maxX, y: box.midY),
                CGPoint(x: box.midX, y: box.maxY),
                CGPoint(x: box.minX, y: box.midY),
            ])
        }
    }

    /// A finder is a 7x7 frame with a 3x3 pupil, drawn as two shapes so the
    /// light separator ring stays crisp at any size. `scale` grows or shrinks
    /// the whole pattern about its centre, radii included.
    static func primitives(for finder: RenderPlan.Finder) -> [Primitive] {
        let s = finder.scale
        let side = 7 * s
        let centre = CGPoint(x: finder.origin.x + 3.5, y: finder.origin.y + 3.5)
        let outer = CGRect(x: centre.x - side / 2, y: centre.y - side / 2, width: side, height: side)
        let inner = outer.insetBy(dx: s, dy: s)
        let pupil = outer.insetBy(dx: 2 * s, dy: 2 * s)
        switch finder.style {
        case .square:
            return [.ring(outer: outer, inner: inner, outerRadius: 0, innerRadius: 0),
                    .rect(pupil)]
        case .rounded:
            return [.ring(outer: outer, inner: inner, outerRadius: 2.0 * s, innerRadius: 1.25 * s),
                    .roundedRect(pupil, radius: 0.9 * s)]
        case .circle:
            return [.ring(outer: outer, inner: inner, outerRadius: 3.5 * s, innerRadius: 2.5 * s),
                    .ellipse(pupil)]
        }
    }
}
