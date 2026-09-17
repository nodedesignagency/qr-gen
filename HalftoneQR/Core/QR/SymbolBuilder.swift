import Foundation

/// Lays out a QR symbol module by module.
///
/// The builder draws the function patterns and the interleaved codewords once,
/// then `finish(mask:)` can be called repeatedly to produce each of the eight
/// masked variants cheaply — which is what lets the app pick the mask that best
/// matches the artwork.
struct SymbolBuilder {

    let version: Int
    let correction: QRErrorCorrection
    let size: Int

    private var modules: [Bool]
    private var functionMap: [Bool]

    init(version: Int, correction: QRErrorCorrection) {
        self.version = version
        self.correction = correction
        self.size = QRVersion.size(of: version)
        self.modules = [Bool](repeating: false, count: size * size)
        self.functionMap = [Bool](repeating: false, count: size * size)
    }

    private mutating func setFunctionModule(_ x: Int, _ y: Int, _ isDark: Bool) {
        guard x >= 0, x < size, y >= 0, y < size else { return }
        modules[y * size + x] = isDark
        functionMap[y * size + x] = true
    }

    // MARK: - Function patterns

    mutating func drawFunctionPatterns() {
        // Timing patterns run the full width and height along row and column 6.
        for index in 0..<size {
            setFunctionModule(6, index, index % 2 == 0)
            setFunctionModule(index, 6, index % 2 == 0)
        }

        // Finder patterns, including their separators, in three corners.
        drawFinderPattern(centreX: 3, centreY: 3)
        drawFinderPattern(centreX: size - 4, centreY: 3)
        drawFinderPattern(centreX: 3, centreY: size - 4)

        // Alignment patterns everywhere except the three finder corners.
        let positions = QRVersion.alignmentPatternPositions(version: version)
        let count = positions.count
        for i in 0..<count {
            for j in 0..<count {
                let isFinderCorner = (i == 0 && j == 0)
                    || (i == 0 && j == count - 1)
                    || (i == count - 1 && j == 0)
                if !isFinderCorner {
                    drawAlignmentPattern(centreX: positions[i], centreY: positions[j])
                }
            }
        }

        // Format bits are drawn again by finish(mask:); this reserves their cells.
        drawFormatBits(mask: 0)
        drawVersionBits()
    }

    private mutating func drawFinderPattern(centreX: Int, centreY: Int) {
        for dy in -4...4 {
            for dx in -4...4 {
                // Chebyshev distance gives the concentric ring structure, and the
                // outermost ring (distance 4) is the light separator.
                let ring = max(abs(dx), abs(dy))
                setFunctionModule(centreX + dx, centreY + dy, ring != 2 && ring != 4)
            }
        }
    }

    private mutating func drawAlignmentPattern(centreX: Int, centreY: Int) {
        for dy in -2...2 {
            for dx in -2...2 {
                setFunctionModule(centreX + dx, centreY + dy, max(abs(dx), abs(dy)) != 1)
            }
        }
    }

    private mutating func drawFormatBits(mask: Int) {
        let data = correction.formatBits << 3 | mask
        // 10-bit BCH remainder, then the standard mask to avoid an all-zero field.
        var remainder = data
        for _ in 0..<10 {
            remainder = (remainder << 1) ^ ((remainder >> 9) * 0x537)
        }
        let bits = (data << 10 | remainder) ^ 0x5412

        // First copy, wrapped around the top-left finder.
        for i in 0...5 {
            setFunctionModule(8, i, bit(bits, i))
        }
        setFunctionModule(8, 7, bit(bits, 6))
        setFunctionModule(8, 8, bit(bits, 7))
        setFunctionModule(7, 8, bit(bits, 8))
        for i in 9..<15 {
            setFunctionModule(14 - i, 8, bit(bits, i))
        }

        // Second copy, split between the other two finders.
        for i in 0..<8 {
            setFunctionModule(size - 1 - i, 8, bit(bits, i))
        }
        for i in 8..<15 {
            setFunctionModule(8, size - 15 + i, bit(bits, i))
        }
        setFunctionModule(8, size - 8, true)  // always dark
    }

    private mutating func drawVersionBits() {
        guard version >= 7 else { return }
        var remainder = version
        for _ in 0..<12 {
            remainder = (remainder << 1) ^ ((remainder >> 11) * 0x1F25)
        }
        let bits = version << 12 | remainder
        for i in 0..<18 {
            let isDark = bit(bits, i)
            let a = size - 11 + i % 3
            let b = i / 3
            setFunctionModule(a, b, isDark)
            setFunctionModule(b, a, isDark)
        }
    }

    // MARK: - Data

    /// Walks the zigzag column pairs from bottom-right to top-left, dropping one
    /// bit into each non-function module.
    mutating func drawCodewords(_ data: [UInt8]) {
        var bitIndex = 0
        var right = size - 1
        while right >= 1 {
            if right == 6 { right = 5 }  // column 6 is the vertical timing pattern
            for vertical in 0..<size {
                for offset in 0..<2 {
                    let x = right - offset
                    let isUpward = ((right + 1) & 2) == 0
                    let y = isUpward ? size - 1 - vertical : vertical
                    if !functionMap[y * size + x] && bitIndex < data.count * 8 {
                        modules[y * size + x] = bit(Int(data[bitIndex >> 3]), 7 - (bitIndex & 7))
                        bitIndex += 1
                    }
                }
            }
            right -= 2
        }
    }

    // MARK: - Masking

    /// Produces the finished symbol for one of the eight data masks.
    func finish(mask: Int) -> QRSymbol {
        var masked = modules
        for y in 0..<size {
            for x in 0..<size where !functionMap[y * size + x] {
                if Self.maskCondition(mask, x: x, y: y) {
                    masked[y * size + x].toggle()
                }
            }
        }
        var builder = self
        builder.modules = masked
        builder.drawFormatBits(mask: mask)
        return QRSymbol(version: version, correction: correction, mask: mask,
                        size: size, modules: builder.modules, functionMap: functionMap)
    }

    static func maskCondition(_ mask: Int, x: Int, y: Int) -> Bool {
        switch mask {
        case 0: return (x + y) % 2 == 0
        case 1: return y % 2 == 0
        case 2: return x % 3 == 0
        case 3: return (x + y) % 3 == 0
        case 4: return (x / 3 + y / 2) % 2 == 0
        case 5: return x * y % 2 + x * y % 3 == 0
        case 6: return (x * y % 2 + x * y % 3) % 2 == 0
        case 7: return ((x + y) % 2 + x * y % 3) % 2 == 0
        default: return false
        }
    }

    // MARK: - Penalty scoring

    private static let penaltyRun = 3          // N1: runs of five or more
    private static let penaltyBlock = 3        // N2: 2x2 blocks of one colour
    private static let penaltyFinderLike = 40  // N3: false finder patterns
    private static let penaltyBalance = 10     // N4: dark/light imbalance

    /// The specification's mask-quality heuristic. Lower is better.
    static func penalty(for symbol: QRSymbol) -> Int {
        let size = symbol.size
        var result = 0

        for axis in 0..<2 {
            for line in 0..<size {
                var runColor = false
                var runLength = 0
                var history = [Int](repeating: 0, count: 7)
                for position in 0..<size {
                    let isDark = axis == 0
                        ? symbol.isDark(x: position, y: line)
                        : symbol.isDark(x: line, y: position)
                    if isDark == runColor {
                        runLength += 1
                        if runLength == 5 { result += penaltyRun }
                        else if runLength > 5 { result += 1 }
                    } else {
                        addRunToHistory(runLength, &history, size: size)
                        if !runColor {
                            result += countFinderLikePatterns(history) * penaltyFinderLike
                        }
                        runColor = isDark
                        runLength = 1
                    }
                }
                result += terminateRunAndCount(runColor, runLength, &history, size: size)
                    * penaltyFinderLike
            }
        }

        for y in 0..<(size - 1) {
            for x in 0..<(size - 1) {
                let color = symbol.isDark(x: x, y: y)
                if color == symbol.isDark(x: x + 1, y: y),
                   color == symbol.isDark(x: x, y: y + 1),
                   color == symbol.isDark(x: x + 1, y: y + 1) {
                    result += penaltyBlock
                }
            }
        }

        var dark = 0
        for y in 0..<size {
            for x in 0..<size where symbol.isDark(x: x, y: y) { dark += 1 }
        }
        let total = size * size
        // How many 5% steps the dark ratio strays from 50%.
        let deviation = (abs(dark * 20 - total * 10) + total - 1) / total - 1
        result += deviation * penaltyBalance

        return result
    }

    private static func addRunToHistory(_ runLength: Int, _ history: inout [Int], size: Int) {
        var length = runLength
        if history[0] == 0 {
            length += size  // the quiet zone extends the very first run
        }
        history.removeLast()
        history.insert(length, at: 0)
    }

    private static func terminateRunAndCount(_ runColor: Bool, _ runLength: Int,
                                             _ history: inout [Int], size: Int) -> Int {
        var length = runLength
        if runColor {
            addRunToHistory(length, &history, size: size)
            length = 0
        }
        length += size  // light quiet zone after the final run
        addRunToHistory(length, &history, size: size)
        return countFinderLikePatterns(history)
    }

    /// Counts 1:1:3:1:1 finder-like sequences in the last seven runs.
    private static func countFinderLikePatterns(_ history: [Int]) -> Int {
        let unit = history[1]
        let hasCore = unit > 0
            && history[2] == unit
            && history[3] == unit * 3
            && history[4] == unit
            && history[5] == unit
        guard hasCore else { return 0 }
        return (history[0] >= unit * 4 && history[6] >= unit ? 1 : 0)
            + (history[6] >= unit * 4 && history[0] >= unit ? 1 : 0)
    }
}

/// Reads bit `index` of `value`, counting from the least significant bit.
private func bit(_ value: Int, _ index: Int) -> Bool {
    (value >> index) & 1 == 1
}
