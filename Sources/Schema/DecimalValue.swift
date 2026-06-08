extension PureXML.Schema {
    /// An exact decimal value, parsed from an XSD `decimal`/`integer` lexical form
    /// and compared without floating-point loss. Holds the sign and the
    /// significant integer and fraction digits (leading and trailing zeros
    /// removed), which is also what `totalDigits` and `fractionDigits` count.
    struct DecimalValue: Equatable, Comparable, Sendable {
        let negative: Bool
        let integerDigits: [Character]
        let fractionDigits: [Character]

        /// Parses a decimal lexical form. With `allowFraction` false the value must
        /// be an integer (no decimal point).
        init?(_ lexical: String, allowFraction: Bool) {
            var characters = Array(lexical)
            guard !characters.isEmpty else { return nil }

            var negative = false
            if characters.first == "+" || characters.first == "-" {
                negative = characters.first == "-"
                characters.removeFirst()
            }
            guard !characters.isEmpty else { return nil }

            let parts = Self.split(characters)
            guard let (whole, fraction) = parts, allowFraction || fraction == nil else { return nil }
            guard whole.allSatisfy(\.isNumber), (fraction ?? []).allSatisfy(\.isNumber) else { return nil }
            guard !whole.isEmpty || !(fraction ?? []).isEmpty else { return nil }

            let integerDigits = Self.dropLeadingZeros(whole)
            let fractionDigits = Self.dropTrailingZeros(fraction ?? [])
            self.integerDigits = integerDigits
            self.fractionDigits = fractionDigits
            // Negative zero is the same value as zero.
            self.negative = (integerDigits.isEmpty && fractionDigits.isEmpty) ? false : negative
        }

        /// Splits the digits on a single decimal point, rejecting a second point.
        /// Returns nil when malformed.
        private static func split(_ characters: [Character]) -> (whole: [Character], fraction: [Character]?)? {
            guard let dot = characters.firstIndex(of: ".") else { return (characters, nil) }
            let rest = characters[(dot + 1)...]
            guard !rest.contains(".") else { return nil }
            return (Array(characters[..<dot]), Array(rest))
        }

        private static func dropLeadingZeros(_ digits: [Character]) -> [Character] {
            Array(digits.drop { $0 == "0" })
        }

        private static func dropTrailingZeros(_ digits: [Character]) -> [Character] {
            var digits = digits
            while digits.last == "0" {
                digits.removeLast()
            }
            return digits
        }

        var isZero: Bool {
            integerDigits.isEmpty && fractionDigits.isEmpty
        }

        /// The XSD `totalDigits` of the value: every significant digit, at least one.
        var totalDigits: Int {
            Swift.max(1, integerDigits.count + fractionDigits.count)
        }

        static func < (lhs: DecimalValue, rhs: DecimalValue) -> Bool {
            if lhs.negative != rhs.negative { return lhs.negative }
            let magnitude = compareMagnitude(lhs, rhs)
            return lhs.negative ? magnitude > 0 : magnitude < 0
        }

        /// Negative when `lhs` has the smaller magnitude, positive when larger.
        private static func compareMagnitude(_ lhs: DecimalValue, _ rhs: DecimalValue) -> Int {
            if lhs.integerDigits.count != rhs.integerDigits.count {
                return lhs.integerDigits.count < rhs.integerDigits.count ? -1 : 1
            }
            if let order = lexicographic(lhs.integerDigits, rhs.integerDigits) { return order }
            return lexicographic(lhs.fractionDigits, rhs.fractionDigits) ?? 0
        }

        /// Digit-by-digit comparison; a proper prefix is the smaller value. Returns
        /// nil when the sequences are identical.
        private static func lexicographic(_ lhs: [Character], _ rhs: [Character]) -> Int? {
            for (left, right) in zip(lhs, rhs) where left != right {
                return left < right ? -1 : 1
            }
            if lhs.count == rhs.count { return nil }
            return lhs.count < rhs.count ? -1 : 1
        }
    }
}
