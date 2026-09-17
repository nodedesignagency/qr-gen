import Foundation

/// The four error-correction levels defined by the QR Code standard, ordered by
/// increasing redundancy.
enum QRErrorCorrection: Int, CaseIterable, Sendable {
    case low = 0, medium, quartile, high

    /// The two-bit value written into the format information area.
    var formatBits: Int {
        switch self {
        case .low: return 1
        case .medium: return 0
        case .quartile: return 3
        case .high: return 2
        }
    }

    /// Roughly how much of the symbol can be destroyed and still recovered.
    var recoveryFraction: Double {
        switch self {
        case .low: return 0.07
        case .medium: return 0.15
        case .quartile: return 0.25
        case .high: return 0.30
        }
    }

    var label: String {
        switch self {
        case .low: return "L"
        case .medium: return "M"
        case .quartile: return "Q"
        case .high: return "H"
        }
    }
}

/// Static per-version geometry and capacity tables from ISO/IEC 18004.
enum QRVersion {

    static let minimum = 1
    static let maximum = 40

    /// Side length of the symbol in modules, excluding the quiet zone.
    static func size(of version: Int) -> Int {
        version * 4 + 17
    }

    /// Number of error-correction codewords in each block, indexed
    /// `[errorCorrectionLevel][version]`. Index 0 of each row is unused.
    static let eccCodewordsPerBlock: [[Int]] = [
        // 0   1   2   3   4   5   6   7   8   9  10  11  12  13  14  15  16  17  18  19  20  21  22  23  24  25  26  27  28  29  30  31  32  33  34  35  36  37  38  39  40
        [ -1,  7, 10, 15, 20, 26, 18, 20, 24, 30, 18, 20, 24, 26, 30, 22, 24, 28, 30, 28, 28, 28, 28, 30, 30, 26, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [ -1, 10, 16, 26, 18, 24, 16, 18, 22, 22, 26, 30, 22, 22, 24, 24, 28, 28, 26, 26, 26, 26, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28, 28],
        [ -1, 13, 22, 18, 26, 18, 24, 18, 22, 20, 24, 28, 26, 24, 20, 30, 24, 28, 28, 26, 30, 28, 30, 30, 30, 30, 28, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
        [ -1, 17, 28, 22, 16, 22, 28, 26, 26, 24, 28, 24, 28, 22, 24, 24, 30, 28, 28, 26, 28, 30, 24, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30, 30],
    ]

    /// Number of error-correction blocks, indexed `[errorCorrectionLevel][version]`.
    static let eccBlockCount: [[Int]] = [
        // 0  1  2  3  4  5  6  7  8  9 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31 32 33 34 35 36 37 38 39 40
        [ -1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 4, 4, 4, 4, 4, 6, 6, 6, 6, 7, 8, 8, 9, 9, 10, 12, 12, 12, 13, 14, 15, 16, 17, 18, 19, 19, 20, 21, 22, 24, 25],
        [ -1, 1, 1, 1, 2, 2, 4, 4, 4, 5, 5, 5, 8, 9, 9, 10, 10, 11, 13, 14, 16, 17, 17, 18, 20, 21, 23, 25, 26, 28, 29, 31, 33, 35, 37, 38, 40, 43, 45, 47, 49],
        [ -1, 1, 1, 2, 2, 4, 4, 6, 6, 8, 8, 8, 10, 12, 16, 12, 17, 16, 18, 21, 20, 23, 23, 25, 27, 29, 34, 34, 35, 38, 40, 43, 45, 48, 51, 53, 56, 59, 62, 65, 68],
        [ -1,  1,  1,  2,  4,  4,  4,  5,  6,  8,  8, 11, 11, 16, 16, 18, 16, 19, 21, 25, 25, 25, 34, 30, 32, 35, 37, 40, 42, 45, 48, 51, 54, 57, 60, 63, 66, 70, 74, 77, 81],
    ]

    /// Total number of data bits available before error correction, i.e. every
    /// module that is not part of a function pattern.
    static func rawDataModules(of version: Int) -> Int {
        precondition((minimum...maximum).contains(version))
        var result = (16 * version + 128) * version + 64
        if version >= 2 {
            let alignmentCount = version / 7 + 2
            result -= (25 * alignmentCount - 10) * alignmentCount - 55
            if version >= 7 {
                result -= 36  // two 6x3 version information blocks
            }
        }
        return result
    }

    /// Number of usable data codewords once error correction is subtracted.
    static func dataCodewords(version: Int, correction: QRErrorCorrection) -> Int {
        rawDataModules(of: version) / 8
            - eccCodewordsPerBlock[correction.rawValue][version]
            * eccBlockCount[correction.rawValue][version]
    }

    /// Centre coordinates of the alignment patterns, on both axes.
    static func alignmentPatternPositions(version: Int) -> [Int] {
        guard version > 1 else { return [] }
        let count = version / 7 + 2
        let step = version == 32 ? 26 : (version * 4 + count * 2 + 1) / (count * 2 - 2) * 2
        var result = [Int](repeating: 0, count: count)
        result[0] = 6
        var position = size(of: version) - 7
        for index in stride(from: count - 1, through: 1, by: -1) {
            result[index] = position
            position -= step
        }
        return result
    }
}
