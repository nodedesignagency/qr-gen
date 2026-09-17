import Foundation

/// An append-only sequence of bits, most significant bit first.
struct QRBitBuffer: Sendable {

    private(set) var bits: [Bool] = []

    var bitCount: Int { bits.count }

    init() {}

    /// Appends the low `bitCount` bits of `value`, most significant first.
    mutating func append(_ value: Int, bitCount: Int) {
        precondition(bitCount >= 0 && bitCount <= 31, "bit count out of range")
        precondition(value >> bitCount == 0, "value does not fit in \(bitCount) bits")
        for shift in stride(from: bitCount - 1, through: 0, by: -1) {
            bits.append((value >> shift) & 1 == 1)
        }
    }

    mutating func append(contentsOf other: QRBitBuffer) {
        bits.append(contentsOf: other.bits)
    }

    mutating func appendBit(_ bit: Bool) {
        bits.append(bit)
    }

    /// Packs the buffer into bytes, zero-padding the final partial byte.
    func bytes() -> [UInt8] {
        var result = [UInt8](repeating: 0, count: (bits.count + 7) / 8)
        for (index, bit) in bits.enumerated() where bit {
            result[index >> 3] |= UInt8(1 << (7 - (index & 7)))
        }
        return result
    }
}
