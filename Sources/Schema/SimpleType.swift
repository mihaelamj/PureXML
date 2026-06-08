public extension PureXML.Schema {
    /// The constraining facets of a simple type. Every facet is optional; an unset
    /// facet imposes no constraint. `patterns` are combined with AND.
    struct Facets: Sendable {
        public var length: Int?
        public var minLength: Int?
        public var maxLength: Int?
        public var patterns: [String]
        public var enumeration: [String]?
        public var whiteSpace: WhiteSpace?
        public var minInclusive: String?
        public var maxInclusive: String?
        public var minExclusive: String?
        public var maxExclusive: String?
        public var totalDigits: Int?
        public var fractionDigits: Int?

        public init(
            length: Int? = nil,
            minLength: Int? = nil,
            maxLength: Int? = nil,
            patterns: [String] = [],
            enumeration: [String]? = nil,
            whiteSpace: WhiteSpace? = nil,
            minInclusive: String? = nil,
            maxInclusive: String? = nil,
            minExclusive: String? = nil,
            maxExclusive: String? = nil,
            totalDigits: Int? = nil,
            fractionDigits: Int? = nil,
        ) {
            self.length = length
            self.minLength = minLength
            self.maxLength = maxLength
            self.patterns = patterns
            self.enumeration = enumeration
            self.whiteSpace = whiteSpace
            self.minInclusive = minInclusive
            self.maxInclusive = maxInclusive
            self.minExclusive = minExclusive
            self.maxExclusive = maxExclusive
            self.totalDigits = totalDigits
            self.fractionDigits = fractionDigits
        }
    }

    /// A simple type: a built-in base restricted by facets. Validates a lexical
    /// value against the XSD Part 2 rules: whitespace processing, the base value
    /// space, the base's intrinsic bounds, then the facets.
    struct SimpleType: Sendable {
        public var base: BuiltinType
        public var facets: Facets

        public init(base: BuiltinType, facets: Facets = Facets()) {
            self.base = base
            self.facets = facets
        }

        /// Whether `lexical` is a valid value of this type.
        public func isValid(_ lexical: String) -> Bool {
            validate(lexical) == nil
        }

        /// A description of the first constraint `lexical` violates, or nil when it
        /// is valid.
        public func validate(_ lexical: String) -> String? {
            let value = Self.process(lexical, whiteSpace: facets.whiteSpace ?? base.whiteSpace)
            let primitive = base.primitive
            guard primitive.isValid(value) else {
                return "'\(lexical)' is not a valid \(base.rawValue)"
            }
            return boundsError(value, primitive)
                ?? lengthError(value, primitive)
                ?? digitsError(value)
                ?? patternError(value)
                ?? enumerationError(value, primitive)
                ?? rangeError(value, primitive)
        }

        // MARK: Whitespace

        static func process(_ value: String, whiteSpace: WhiteSpace) -> String {
            switch whiteSpace {
            case .preserve:
                return value
            case .replace:
                return String(value.map { ($0 == "\t" || $0 == "\n" || $0 == "\r") ? " " : $0 })
            case .collapse:
                let replaced = value.map { ($0 == "\t" || $0 == "\n" || $0 == "\r") ? " " : $0 }
                return String(replaced).split(separator: " ").joined(separator: " ")
            }
        }

        // MARK: Facet checks

        private func boundsError(_ value: String, _: Primitive) -> String? {
            let (lower, upper) = base.bounds
            guard lower != nil || upper != nil, let decimal = DecimalValue(value, allowFraction: false) else {
                return nil
            }
            if let lower, decimal < lower { return "\(value) is below the minimum for \(base.rawValue)" }
            if let upper, decimal > upper { return "\(value) is above the maximum for \(base.rawValue)" }
            return nil
        }

        private func lengthError(_ value: String, _ primitive: Primitive) -> String? {
            let length = primitive.measuredLength(value)
            if let exact = facets.length, length != exact { return "length \(length) is not \(exact)" }
            if let minimum = facets.minLength, length < minimum { return "length \(length) is below \(minimum)" }
            if let maximum = facets.maxLength, length > maximum { return "length \(length) is above \(maximum)" }
            return nil
        }

        private func digitsError(_ value: String) -> String? {
            guard facets.totalDigits != nil || facets.fractionDigits != nil,
                  let decimal = DecimalValue(value, allowFraction: true) else { return nil }
            if let total = facets.totalDigits, decimal.totalDigits > total { return "more than \(total) total digits" }
            if let fraction = facets.fractionDigits, decimal.fractionDigits.count > fraction {
                return "more than \(fraction) fraction digits"
            }
            return nil
        }

        private func patternError(_ value: String) -> String? {
            for pattern in facets.patterns {
                guard let regex = try? PureXML.Regex.Pattern(pattern), regex.matches(value) else {
                    return "'\(value)' does not match pattern '\(pattern)'"
                }
            }
            return nil
        }

        private func enumerationError(_ value: String, _ primitive: Primitive) -> String? {
            guard let enumeration = facets.enumeration else { return nil }
            let whiteSpace = facets.whiteSpace ?? base.whiteSpace
            let matched = enumeration.contains { candidate in
                let normalized = Self.process(candidate, whiteSpace: whiteSpace)
                if let lhs = primitive.ordered(value), let rhs = primitive.ordered(normalized) { return lhs == rhs }
                return normalized == value
            }
            return matched ? nil : "'\(value)' is not in the enumeration"
        }

        private func rangeError(_ value: String, _ primitive: Primitive) -> String? {
            guard let actual = primitive.ordered(value) else { return nil }
            if let bound = facets.minInclusive, let limit = primitive.ordered(bound), actual < limit {
                return "\(value) is below the inclusive minimum"
            }
            if let bound = facets.maxInclusive, let limit = primitive.ordered(bound), actual > limit {
                return "\(value) is above the inclusive maximum"
            }
            if let bound = facets.minExclusive, let limit = primitive.ordered(bound), !(limit < actual) {
                return "\(value) is not above the exclusive minimum"
            }
            if let bound = facets.maxExclusive, let limit = primitive.ordered(bound), !(actual < limit) {
                return "\(value) is not below the exclusive maximum"
            }
            return nil
        }
    }

    /// Validates `value` against a built-in type with no extra facets.
    static func isValid(_ value: String, type: BuiltinType) -> Bool {
        SimpleType(base: type).isValid(value)
    }
}
