public extension PureXML.XPath {
    /// An XPath 1.0 value: one of the four types the expression language operates
    /// on. Every expression evaluates to one of these, and the conversion methods
    /// implement the spec's coercion rules used by operators and functions.
    /// A runtime value (a node-set holds live tree nodes), not a `Sendable`.
    enum Value: Equatable {
        case nodeSet([Node])
        case boolean(Bool)
        case number(Double)
        case string(String)

        /// The boolean() coercion: a node-set is true when non-empty, a number
        /// when non-zero and not NaN, a string when non-empty.
        public var boolean: Bool {
            switch self {
            case let .nodeSet(nodes): !nodes.isEmpty
            case let .boolean(value): value
            case let .number(value): value != 0 && !value.isNaN
            case let .string(value): !value.isEmpty
            }
        }

        /// The number() coercion: booleans map to 1/0, strings parse per the XPath
        /// grammar (else NaN), and a node-set converts through its string-value.
        public var number: Double {
            switch self {
            case .nodeSet: Self.parseNumber(string)
            case let .boolean(value): value ? 1 : 0
            case let .number(value): value
            case let .string(value): Self.parseNumber(value)
            }
        }

        /// The string() coercion: booleans render as `true`/`false`, numbers in the
        /// XPath canonical form, and a node-set as the string-value of its first
        /// node in document order (empty when the set is empty).
        public var string: String {
            switch self {
            case let .nodeSet(nodes):
                guard let first = nodes.min(by: Node.precedes) else { return "" }
                return first.stringValue
            case let .boolean(value): return value ? "true" : "false"
            case let .number(value): return Self.format(value)
            case let .string(value): return value
            }
        }

        /// The node-set, or nil when the value is not a node-set.
        public var nodes: [Node]? {
            guard case let .nodeSet(nodes) = self else { return nil }
            return nodes
        }

        /// Formats a number in the XPath canonical form: `NaN`, `Infinity`, an
        /// integer without a decimal point, or the shortest round-tripping decimal.
        /// XPath 1.0 forbids exponential notation, so any exponent in the shortest
        /// representation is expanded to a plain decimal.
        static func format(_ value: Double) -> String {
            if value.isNaN { return "NaN" }
            if value.isInfinite { return value < 0 ? "-Infinity" : "Infinity" }
            if value == value.rounded(), abs(value) < 1e15 {
                return String(Int64(value))
            }
            return expandExponent(String(value))
        }

        /// Rewrites a Swift double rendering into a plain decimal without an
        /// exponent: `1.5e-05` becomes `0.000015`, `1.23e+21` becomes
        /// `1230000000000000000000`.
        private static func expandExponent(_ text: String) -> String {
            let lowered = text.lowercased()
            guard let exponentIndex = lowered.firstIndex(of: "e") else { return text }
            let mantissa = String(lowered[lowered.startIndex ..< exponentIndex])
            guard let exponent = Int(lowered[lowered.index(after: exponentIndex)...]) else { return text }
            let negative = mantissa.hasPrefix("-")
            let unsigned = negative ? String(mantissa.dropFirst()) : mantissa
            let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
            let integerDigits = String(parts.first ?? "")
            let fractionDigits = parts.count > 1 ? String(parts[1]) : ""
            var digits = Array(integerDigits + fractionDigits)
            // The decimal point currently sits after `integerDigits`; the exponent
            // shifts it right (positive) or left (negative).
            var point = integerDigits.count + exponent
            if point <= 0 {
                digits = Array(repeating: "0", count: 1 - point) + digits
                point = 1
            } else if point > digits.count {
                digits += Array(repeating: "0", count: point - digits.count)
            }
            let integerPart = String(digits[0 ..< point])
            let fractionPart = String(digits[point...])
            let body = fractionPart.isEmpty ? integerPart : "\(integerPart).\(trimTrailingZeros(fractionPart))"
            return (negative ? "-" : "") + body
        }

        private static func trimTrailingZeros(_ fraction: String) -> String {
            var trimmed = fraction
            while trimmed.count > 1, trimmed.hasSuffix("0") {
                trimmed.removeLast()
            }
            return trimmed
        }

        /// Parses a string to a number per the XPath `Number` grammar: optional
        /// surrounding whitespace, an optional sign, and digits with an optional
        /// single decimal point. Anything else is NaN.
        static func parseNumber(_ raw: String) -> Double {
            let trimmed = raw.trimmingXMLWhitespace()
            guard !trimmed.isEmpty else { return .nan }
            var seenDot = false
            var digits = 0
            for (offset, character) in trimmed.enumerated() {
                if character == "-", offset == 0 { continue }
                if character == "." {
                    if seenDot { return .nan }
                    seenDot = true
                    continue
                }
                guard character.isNumber else { return .nan }
                digits += 1
            }
            guard digits > 0 else { return .nan }
            return Double(trimmed) ?? .nan
        }
    }
}
