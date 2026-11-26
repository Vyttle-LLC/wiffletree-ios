import Foundation

extension Data {
    /// Bytes from hex text, either case; nil for anything else.
    init?(hex: String) {
        let digits = Array(hex.utf8)
        guard digits.count.isMultiple(of: 2) else { return nil }
        var bytes = [UInt8]()
        bytes.reserveCapacity(digits.count / 2)
        for index in stride(from: 0, to: digits.count, by: 2) {
            guard let high = Self.nibble(digits[index]), let low = Self.nibble(digits[index + 1]) else { return nil }
            bytes.append(high << 4 | low)
        }
        self.init(bytes)
    }

    /// The bytes in lowercase hex.
    var hex: String {
        map { String(format: "%02x", $0) }.joined()
    }

    private static func nibble(_ digit: UInt8) -> UInt8? {
        switch digit {
        case UInt8(ascii: "0")...UInt8(ascii: "9"): digit - UInt8(ascii: "0")
        case UInt8(ascii: "a")...UInt8(ascii: "f"): digit - UInt8(ascii: "a") + 10
        case UInt8(ascii: "A")...UInt8(ascii: "F"): digit - UInt8(ascii: "A") + 10
        default: nil
        }
    }
}
