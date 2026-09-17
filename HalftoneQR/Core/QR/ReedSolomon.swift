import Foundation

/// Arithmetic in the Galois field GF(2^8/0x11D), as used by QR Code error correction.
///
/// Every value is a byte interpreted as a polynomial over GF(2); multiplication is
/// polynomial multiplication reduced modulo the primitive polynomial
/// `x^8 + x^4 + x^3 + x^2 + 1` (0x11D).
enum ReedSolomon {

    /// Multiplies two field elements. Both operands and the result are in 0...255.
    static func multiply(_ x: Int, _ y: Int) -> Int {
        assert(x >> 8 == 0 && y >> 8 == 0, "operands must be bytes")
        var z = 0
        // Russian-peasant multiplication with reduction folded into each step.
        for i in stride(from: 7, through: 0, by: -1) {
            z = (z << 1) ^ ((z >> 7) * 0x11D)
            z ^= ((y >> i) & 1) * x
        }
        assert(z >> 8 == 0)
        return z
    }

    /// Returns the coefficients of the generator polynomial of the given degree,
    /// which is the product of `(x - r^i)` for i in 0..<degree, where r = 0x02.
    ///
    /// Coefficients are listed from the highest power down, omitting the leading 1.
    static func divisor(degree: Int) -> [UInt8] {
        precondition((1...255).contains(degree), "degree out of range")
        // Start with the monomial x^0; each iteration multiplies by (x - r^i).
        var result = [UInt8](repeating: 0, count: degree)
        result[degree - 1] = 1
        var root = 1
        for _ in 0..<degree {
            for j in 0..<result.count {
                result[j] = UInt8(multiply(Int(result[j]), root))
                if j + 1 < result.count {
                    result[j] ^= result[j + 1]
                }
            }
            root = multiply(root, 0x02)
        }
        return result
    }

    /// Returns the remainder of `data` divided by `divisor`, which is the block's
    /// error-correction codewords.
    static func remainder(of data: [UInt8], divisor: [UInt8]) -> [UInt8] {
        var result = [UInt8](repeating: 0, count: divisor.count)
        for byte in data {
            let factor = Int(byte ^ result[0])
            result.removeFirst()
            result.append(0)
            for i in 0..<result.count {
                result[i] ^= UInt8(multiply(Int(divisor[i]), factor))
            }
        }
        return result
    }
}
