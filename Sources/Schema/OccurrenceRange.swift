public extension PureXML.Schema {
    /// A non-negative integer magnitude preserved as normalized decimal text.
    ///
    /// XSD occurrence attributes are `nonNegativeInteger` values and may exceed
    /// the platform `Int` range. This type compares such values without converting
    /// them to machine integers.
    struct NonNegativeDecimal: Sendable, Hashable, Comparable, CustomStringConvertible {
        private var digits: String

        public init(_ value: Int) {
            precondition(value >= 0, "occurrence values must be non-negative")
            digits = String(value)
        }

        public init?(lexical value: String) {
            var raw = Substring(value.trimmingXMLWhitespace())
            if raw.first == "+" { raw = raw.dropFirst() }
            guard !raw.isEmpty, raw.allSatisfy({ $0.isASCII && $0.isNumber }) else {
                return nil
            }
            let trimmed = raw.drop { $0 == "0" }
            digits = trimmed.isEmpty ? "0" : String(trimmed)
        }

        public var description: String {
            digits
        }

        var isZero: Bool {
            digits == "0"
        }

        func clamped(to limit: Int) -> Int {
            precondition(limit >= 0, "occurrence clamp limit must be non-negative")
            if isGreaterThan(limit) { return limit }
            return Int(digits) ?? limit
        }

        func isGreaterThan(_ value: Int) -> Bool {
            precondition(value >= 0, "occurrence comparison value must be non-negative")
            let other = String(value)
            if digits.count != other.count { return digits.count > other.count }
            return digits > other
        }

        func isLessThanOrEqual(to value: Int) -> Bool {
            !isGreaterThan(value)
        }

        public static func < (lhs: Self, rhs: Self) -> Bool {
            if lhs.digits.count != rhs.digits.count {
                return lhs.digits.count < rhs.digits.count
            }
            return lhs.digits < rhs.digits
        }
    }

    /// The upper occurrence bound of an XSD particle.
    enum OccurrenceUpper: Sendable, Hashable, Equatable {
        case finite(NonNegativeDecimal)
        case unbounded

        public init(_ value: Int?) {
            if let value {
                self = .finite(NonNegativeDecimal(value))
            } else {
                self = .unbounded
            }
        }

        public var isZero: Bool {
            if case let .finite(value) = self { return value.isZero }
            return false
        }

        func clamped(to limit: Int) -> Int? {
            switch self {
            case let .finite(value): value.clamped(to: limit)
            case .unbounded: nil
            }
        }

        func isGreaterThan(_ value: Int) -> Bool {
            switch self {
            case let .finite(upper): upper.isGreaterThan(value)
            case .unbounded: true
            }
        }
    }

    /// The full occurrence range of an XSD particle.
    struct OccurrenceRange: Sendable, Hashable, Equatable {
        public var minimum: NonNegativeDecimal
        public var maximum: OccurrenceUpper

        public init(minimum: NonNegativeDecimal = NonNegativeDecimal(1), maximum: OccurrenceUpper = .finite(NonNegativeDecimal(1))) {
            self.minimum = minimum
            self.maximum = maximum
        }

        public init(minimum: Int = 1, maximum: Int? = 1) {
            self.minimum = NonNegativeDecimal(minimum)
            self.maximum = OccurrenceUpper(maximum)
        }
    }
}
