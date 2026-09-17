import Foundation

/// A fully built QR symbol: the module matrix plus the map of which modules are
/// function patterns.
///
/// The function map is what makes halftoning possible. Finder, timing, alignment
/// and format modules must be reproduced exactly or detection fails, while data
/// modules only have to be correct at the point a decoder samples them.
struct QRSymbol: Sendable {

    let version: Int
    let correction: QRErrorCorrection
    let mask: Int
    /// Side length in modules, excluding the quiet zone.
    let size: Int

    private let modules: [Bool]
    private let functionMap: [Bool]

    init(version: Int, correction: QRErrorCorrection, mask: Int,
                     size: Int, modules: [Bool], functionMap: [Bool]) {
        self.version = version
        self.correction = correction
        self.mask = mask
        self.size = size
        self.modules = modules
        self.functionMap = functionMap
    }

    /// True when the module at (x, y) is dark. Out-of-bounds reads are light,
    /// which models the quiet zone.
    func isDark(x: Int, y: Int) -> Bool {
        guard x >= 0, x < size, y >= 0, y < size else { return false }
        return modules[y * size + x]
    }

    /// True when the module at (x, y) belongs to a function pattern and must be
    /// rendered exactly.
    func isFunction(x: Int, y: Int) -> Bool {
        guard x >= 0, x < size, y >= 0, y < size else { return true }
        return functionMap[y * size + x]
    }

    /// Chebyshev distance to the nearest function module, capped at `limit`.
    /// Used to reinforce the modules that sit right against the finder patterns.
    func distanceToFunction(x: Int, y: Int, limit: Int) -> Int {
        for radius in 1...max(1, limit) {
            for dy in -radius...radius {
                for dx in -radius...radius where max(abs(dx), abs(dy)) == radius {
                    if isFunction(x: x + dx, y: y + dy) { return radius }
                }
            }
        }
        return limit + 1
    }

    /// Top-left corners of the three finder patterns, in module coordinates.
    var finderOrigins: [(x: Int, y: Int)] {
        [(0, 0), (size - 7, 0), (0, size - 7)]
    }
}

enum QREncodingError: Error, LocalizedError {
    case tooLong(bits: Int)
    case empty

    var errorDescription: String? {
        switch self {
        case .tooLong:
            return "This text is too long to fit in a QR code at this error-correction level."
        case .empty:
            return "Nothing to encode."
        }
    }
}

/// How the data mask is chosen.
enum QRMaskChoice: Sendable {
    /// The standard penalty heuristic from the specification.
    case automatic
    /// Pick the mask whose module layout best matches a target image, with the
    /// standard penalty acting as a tiebreak so the symbol stays scannable.
    ///
    /// The closure receives a candidate symbol and returns a similarity in 0...1.
    case matchingArtwork(@Sendable (QRSymbol) -> Double)
    /// Force a specific mask, 0...7.
    case fixed(Int)
}

enum QREncoder {

    /// Builds the smallest symbol that fits `text` at the given correction level.
    static func encode(text: String,
                       correction: QRErrorCorrection = .high,
                       maskChoice: QRMaskChoice = .automatic) throws -> QRSymbol {
        guard !text.isEmpty else { throw QREncodingError.empty }
        let segments = QRSegment.segments(for: text)

        // Smallest version whose data capacity holds the payload.
        var chosenVersion: Int?
        var payloadBits = 0
        for version in QRVersion.minimum...QRVersion.maximum {
            let capacity = QRVersion.dataCodewords(version: version, correction: correction) * 8
            if let bits = QRSegment.totalBits(segments, version: version), bits <= capacity {
                chosenVersion = version
                payloadBits = bits
                break
            }
        }
        guard let version = chosenVersion else {
            throw QREncodingError.tooLong(bits: payloadBits)
        }

        let codewords = dataCodewords(segments: segments, version: version, correction: correction)
        let interleaved = addErrorCorrectionAndInterleave(codewords, version: version, correction: correction)

        var builder = SymbolBuilder(version: version, correction: correction)
        builder.drawFunctionPatterns()
        builder.drawCodewords(interleaved)

        switch maskChoice {
        case .fixed(let mask):
            return builder.finish(mask: mask & 7)

        case .automatic:
            var best = builder.finish(mask: 0)
            var bestPenalty = SymbolBuilder.penalty(for: best)
            for mask in 1...7 {
                let candidate = builder.finish(mask: mask)
                let penalty = SymbolBuilder.penalty(for: candidate)
                if penalty < bestPenalty {
                    best = candidate
                    bestPenalty = penalty
                }
            }
            return best

        case .matchingArtwork(let similarity):
            var candidates: [(symbol: QRSymbol, similarity: Double, penalty: Double)] = []
            for mask in 0...7 {
                let candidate = builder.finish(mask: mask)
                candidates.append((candidate,
                                   similarity(candidate),
                                   Double(SymbolBuilder.penalty(for: candidate))))
            }
            // Normalise the penalties into 0...1 so the two criteria are comparable,
            // then let likeness lead with the penalty as a gentle corrective.
            let penalties = candidates.map(\.penalty)
            let lowest = penalties.min() ?? 0
            let highest = penalties.max() ?? 0
            let spread = max(highest - lowest, 1)
            let best = candidates.max { lhs, rhs in
                let lhsScore = lhs.similarity - 0.25 * ((lhs.penalty - lowest) / spread)
                let rhsScore = rhs.similarity - 0.25 * ((rhs.penalty - lowest) / spread)
                return lhsScore < rhsScore
            }
            return best!.symbol
        }
    }

    // MARK: - Bit stream

    private static func dataCodewords(segments: [QRSegment], version: Int,
                                      correction: QRErrorCorrection) -> [UInt8] {
        let capacity = QRVersion.dataCodewords(version: version, correction: correction) * 8
        var buffer = QRBitBuffer()
        for segment in segments {
            buffer.append(segment.mode.indicator, bitCount: 4)
            buffer.append(segment.characterCount,
                          bitCount: segment.mode.characterCountBits(version: version))
            buffer.append(contentsOf: segment.data)
        }
        // Terminator, then pad to a byte boundary.
        buffer.append(0, bitCount: min(4, capacity - buffer.bitCount))
        buffer.append(0, bitCount: (8 - buffer.bitCount % 8) % 8)
        // Alternating pad codewords fill the remainder.
        var pad: UInt8 = 0xEC
        while buffer.bitCount < capacity {
            buffer.append(Int(pad), bitCount: 8)
            pad ^= 0xEC ^ 0x11
        }
        return buffer.bytes()
    }

    /// Splits the data into blocks, appends each block's error-correction
    /// codewords and interleaves the result in the order the standard specifies.
    private static func addErrorCorrectionAndInterleave(_ data: [UInt8], version: Int,
                                                        correction: QRErrorCorrection) -> [UInt8] {
        let blockCount = QRVersion.eccBlockCount[correction.rawValue][version]
        let eccLength = QRVersion.eccCodewordsPerBlock[correction.rawValue][version]
        let rawCodewords = QRVersion.rawDataModules(of: version) / 8
        let shortBlockCount = blockCount - rawCodewords % blockCount
        let shortBlockLength = rawCodewords / blockCount

        let divisor = ReedSolomon.divisor(degree: eccLength)
        var blocks: [[UInt8]] = []
        blocks.reserveCapacity(blockCount)
        var cursor = 0
        for index in 0..<blockCount {
            let dataLength = shortBlockLength - eccLength + (index < shortBlockCount ? 0 : 1)
            let chunk = Array(data[cursor..<(cursor + dataLength)])
            cursor += dataLength
            // Every block is padded to the long length so interleaving is uniform;
            // the extra byte in short blocks is skipped when reading back out.
            var block = chunk + [UInt8](repeating: 0, count: shortBlockLength + 1 - chunk.count)
            let ecc = ReedSolomon.remainder(of: chunk, divisor: divisor)
            block.replaceSubrange((block.count - eccLength)..<block.count, with: ecc)
            blocks.append(block)
        }

        var result: [UInt8] = []
        result.reserveCapacity(rawCodewords)
        for position in 0..<blocks[0].count {
            for (blockIndex, block) in blocks.enumerated() {
                let isPaddingSlot = position == shortBlockLength - eccLength && blockIndex < shortBlockCount
                if !isPaddingSlot {
                    result.append(block[position])
                }
            }
        }
        return result
    }
}
