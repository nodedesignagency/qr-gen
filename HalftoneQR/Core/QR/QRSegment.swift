import Foundation

/// A run of user data encoded in a single QR mode.
struct QRSegment: Sendable {

    enum Mode: Sendable {
        case numeric, alphanumeric, byte

        /// The four-bit mode indicator written ahead of the character count.
        var indicator: Int {
            switch self {
            case .numeric: return 0x1
            case .alphanumeric: return 0x2
            case .byte: return 0x4
            }
        }

        /// Width of the character-count field, which grows with version.
        func characterCountBits(version: Int) -> Int {
            let index = (version + 7) / 17  // 0 for v1-9, 1 for v10-26, 2 for v27-40
            switch self {
            case .numeric: return [10, 12, 14][index]
            case .alphanumeric: return [9, 11, 13][index]
            case .byte: return [8, 16, 16][index]
            }
        }
    }

    let mode: Mode
    /// Number of characters (not bits) this segment represents.
    let characterCount: Int
    let data: QRBitBuffer

    /// The 45 characters encodable in alphanumeric mode, in value order.
    static let alphanumericCharset = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:")

    // MARK: - Builders

    static func numeric(_ digits: String) -> QRSegment {
        var buffer = QRBitBuffer()
        let characters = Array(digits)
        var index = 0
        while index < characters.count {
            let run = min(3, characters.count - index)
            let value = Int(String(characters[index..<(index + run)]))!
            buffer.append(value, bitCount: run * 3 + 1)
            index += run
        }
        return QRSegment(mode: .numeric, characterCount: characters.count, data: buffer)
    }

    static func alphanumeric(_ text: String) -> QRSegment {
        var buffer = QRBitBuffer()
        let values = text.map { alphanumericCharset.firstIndex(of: $0)! }
        var index = 0
        while index + 1 < values.count {
            buffer.append(values[index] * 45 + values[index + 1], bitCount: 11)
            index += 2
        }
        if index < values.count {
            buffer.append(values[index], bitCount: 6)
        }
        return QRSegment(mode: .alphanumeric, characterCount: values.count, data: buffer)
    }

    static func byte(_ bytes: [UInt8]) -> QRSegment {
        var buffer = QRBitBuffer()
        for byte in bytes {
            buffer.append(Int(byte), bitCount: 8)
        }
        return QRSegment(mode: .byte, characterCount: bytes.count, data: buffer)
    }

    // MARK: - Mode selection

    private static func isNumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { $0.isASCII && $0.isNumber }
    }

    private static func isAlphanumeric(_ text: String) -> Bool {
        !text.isEmpty && text.allSatisfy { alphanumericCharset.contains($0) }
    }

    /// Chooses the most compact single-mode representation of `text`.
    ///
    /// Mixed-mode segmentation would occasionally save a few bits, but a URL is
    /// almost always uniformly one mode and the extra mode headers usually cost
    /// more than they save.
    static func segments(for text: String) -> [QRSegment] {
        if text.isEmpty { return [] }
        if isNumeric(text) { return [numeric(text)] }
        if isAlphanumeric(text) { return [alphanumeric(text)] }
        return [byte(Array(text.utf8))]
    }

    /// Total encoded size of `segments` at the given version, or nil on overflow.
    static func totalBits(_ segments: [QRSegment], version: Int) -> Int? {
        var total = 0
        for segment in segments {
            let countBits = segment.mode.characterCountBits(version: version)
            // A segment whose character count does not fit its field is unencodable.
            guard segment.characterCount < (1 << countBits) else { return nil }
            total += 4 + countBits + segment.data.bitCount
            guard total <= Int.max / 2 else { return nil }
        }
        return total
    }
}
