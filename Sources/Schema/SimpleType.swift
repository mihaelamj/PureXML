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

        /// Whether no facet narrows the base type's value space: the type is the
        /// bare built-in. Used to decide whether an `xsi:type` built-in may validly
        /// substitute for a declared type (a faceted restriction may not be the
        /// target of a built-in substitution).
        public var isUnconstrained: Bool {
            length == nil && minLength == nil && maxLength == nil && patterns.isEmpty
                && enumeration == nil && whiteSpace == nil
                && minInclusive == nil && maxInclusive == nil
                && minExclusive == nil && maxExclusive == nil
                && totalDigits == nil && fractionDigits == nil
        }
    }

    /// A simple type's variety (XSD Part 2): atomic, a whitespace-separated list
    /// of an item type, or a union of member types.
    indirect enum Variety: Sendable {
        case atomic
        case list(SimpleType)
        case union([SimpleType])
    }

    /// A simple type: a built-in base restricted by facets, of one of the three
    /// varieties. Validates a lexical value against the XSD Part 2 rules:
    /// whitespace processing, the base value space, the base's intrinsic bounds,
    /// then the facets. A list checks each item against the item type and counts
    /// items for the length facets; a union admits a value valid for any member.
    struct SimpleType: Sendable {
        public var base: BuiltinType
        public var facets: Facets
        public var variety: Variety
        public var isAnySimpleType: Bool

        public init(base: BuiltinType, facets: Facets = Facets(), variety: Variety = .atomic, isAnySimpleType: Bool = false) {
            self.base = base
            self.facets = facets
            self.variety = variety
            self.isAnySimpleType = isAnySimpleType
        }

        /// A list type whose items are `item`, carrying its own (list) facets.
        public static func list(item: SimpleType, facets: Facets = Facets()) -> SimpleType {
            SimpleType(base: .string, facets: facets, variety: .list(item))
        }

        /// A union of `members`: a value is valid if any member admits it.
        public static func union(_ members: [SimpleType]) -> SimpleType {
            SimpleType(base: .string, variety: .union(members))
        }

        /// Whether `lexical` is a valid value of this type.
        public func isValid(_ lexical: String) -> Bool {
            validate(lexical) == nil
        }

        /// A description of the first constraint `lexical` violates, or nil when it
        /// is valid.
        public func validate(_ lexical: String) -> String? {
            switch variety {
            case .atomic: validateAtomic(lexical)
            case let .list(item): validateList(lexical, item: item)
            case let .union(members): validateUnion(lexical, members: members)
            }
        }

        private func validateList(_ lexical: String, item: SimpleType) -> String? {
            let normalized = Self.process(lexical, whiteSpace: facets.whiteSpace ?? .collapse)
            let tokens = normalized.isEmpty ? [] : normalized.split(separator: " ").map(String.init)
            for token in tokens {
                if let error = item.validate(token) { return error }
            }
            if let exact = facets.length, tokens.count != exact { return "list length \(tokens.count) is not \(exact)" }
            if let minimum = facets.minLength, tokens.count < minimum { return "list length \(tokens.count) is below \(minimum)" }
            if let maximum = facets.maxLength, tokens.count > maximum { return "list length \(tokens.count) is above \(maximum)" }
            if let error = patternError(normalized) { return error }
            if let enumeration = facets.enumeration, !enumeration.contains(normalized) {
                return "'\(normalized)' is not in the enumeration"
            }
            return nil
        }

        /// Whether `instance` and `literal` denote the same value in this type's
        /// value space, the comparison a RELAX NG `<value>` performs. Ordered
        /// types (numeric, date/time) compare in value space, so `1` equals `01`
        /// and `1.0` equals `1.00`; booleans treat `1`/`true` and `0`/`false` as
        /// equal. Every other type, including `string`/`token`, compares by its
        /// whitespace-normalized lexical form. (Durations and binary types fall
        /// under the lexical rule, so only their normalized forms compare equal.)
        public func valueMatches(_ instance: String, literal: String) -> Bool {
            switch variety {
            case .atomic:
                return atomicValueMatches(instance, literal)
            case let .list(item):
                let whitespaceProcessing = facets.whiteSpace ?? .collapse
                let leftNorm = Self.process(instance, whiteSpace: whitespaceProcessing)
                let rightNorm = Self.process(literal, whiteSpace: whitespaceProcessing)
                let leftTokens = leftNorm.isEmpty ? [] : leftNorm.split(separator: " ").map(String.init)
                let rightTokens = rightNorm.isEmpty ? [] : rightNorm.split(separator: " ").map(String.init)
                guard leftTokens.count == rightTokens.count else { return false }
                return zip(leftTokens, rightTokens).allSatisfy { item.valueMatches($0, literal: $1) }
            case let .union(members):
                guard let leftMember = members.first(where: { $0.isValid(instance) }),
                      let rightMember = members.first(where: { $0.isValid(literal) }),
                      leftMember.base == rightMember.base
                else { return false }
                return leftMember.valueMatches(instance, literal: literal)
            }
        }

        private func atomicValueMatches(_ instance: String, _ literal: String) -> Bool {
            let whiteSpace = facets.whiteSpace ?? base.whiteSpace
            let left = Self.process(instance, whiteSpace: whiteSpace)
            let right = Self.process(literal, whiteSpace: whiteSpace)
            switch base.primitive {
            case .decimal, .integer, .double, .float, .dateKind:
                guard let leftValue = base.primitive.ordered(left), let rightValue = base.primitive.ordered(right) else { return false }
                return leftValue == rightValue
            case .boolean:
                guard let leftValue = Self.booleanValue(left) else { return false }
                return leftValue == Self.booleanValue(right)
            default:
                return left == right
            }
        }

        private static func booleanValue(_ value: String) -> Bool? {
            switch value {
            case "true", "1": true
            case "false", "0": false
            default: nil
            }
        }

        private func validateUnion(_ lexical: String, members: [SimpleType]) -> String? {
            // The value must be valid against at least one member type.
            guard members.contains(where: { $0.validate(lexical) == nil }) else {
                return "'\(lexical)' does not match any member type of the union"
            }
            // `pattern` and `enumeration` are the only constraining facets XSD
            // allows on a union (Datatypes 4.1.5); both apply on top of membership.
            // Pattern matches the lexical value; enumeration compares in the
            // value space of whichever member admits each value, so `01` equals an
            // enumerated `1` for an integer member, matching the atomic path.
            if let error = patternError(lexical) { return error }
            if let enumeration = facets.enumeration {
                let inEnumeration = enumeration.contains { candidate in
                    members.contains { $0.valueMatches(lexical, literal: candidate) }
                }
                if !inEnumeration { return "'\(lexical)' is not in the enumeration" }
            }
            return nil
        }

        private func validateAtomic(_ lexical: String) -> String? {
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
            // length/minLength/maxLength measure characters, octets, or list
            // items depending on the type; for QName the spec leaves the unit
            // unspecified (XSD 1.0 Datatypes 4.3.1), so like Xerces and the XSTS
            // NIST oracle we do not constrain QName values by length.
            if case .qName = primitive { return nil }
            if case .notation = primitive { return nil }
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
            if case .duration = primitive { return durationRangeError(value) }
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

        /// Ordering facets on `xs:duration`, which is a partial order: a value
        /// that is incomparable to the bound does not satisfy it (it is not in
        /// the ordered range), so an incomparable result is a violation.
        private func durationRangeError(_ value: String) -> String? {
            guard let actual = DurationValue(value) else { return nil }
            func order(_ bound: String?) -> DurationOrder? {
                bound.flatMap(DurationValue.init).map(actual.compare(to:))
            }
            if let order = order(facets.minInclusive), order == .lessThan || order == .incomparable {
                return "\(value) is below the inclusive minimum"
            }
            if let order = order(facets.maxInclusive), order == .greaterThan || order == .incomparable {
                return "\(value) is above the inclusive maximum"
            }
            if let order = order(facets.minExclusive), order != .greaterThan {
                return "\(value) is not above the exclusive minimum"
            }
            if let order = order(facets.maxExclusive), order != .lessThan {
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
