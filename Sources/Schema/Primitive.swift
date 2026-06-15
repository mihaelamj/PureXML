extension PureXML.Schema {
    /// A value compared for the ordering facets (`minInclusive` and friends).
    enum OrderedValue: Equatable, Comparable {
        case decimal(DecimalValue)
        case double(Double)
        case dateTime(DateTimeValue)

        static func < (lhs: OrderedValue, rhs: OrderedValue) -> Bool {
            switch (lhs, rhs) {
            case let (.decimal(left), .decimal(right)): left < right
            case let (.double(left), .double(right)): left < right
            case let (.dateTime(left), .dateTime(right)): left < right
            default: false
            }
        }
    }

    /// An XSD primitive value space: the lexical recognizer, and for the ordered
    /// spaces a value usable by the ordering facets.
    enum Primitive: Sendable {
        case string
        case boolean
        case decimal
        case integer
        case double
        case float
        case duration
        case dateKind(DateKind)
        case hexBinary
        case base64Binary
        case anyURI
        case qName
        case name
        case ncName
        case nmtoken
        case language
        case notation

        func isValid(_ value: String) -> Bool {
            stringValidity(value) ?? numericValidity(value)
        }

        /// Validity for the string-like and boolean spaces; nil when this primitive
        /// is handled by ``numericValidity(_:)``.
        private func stringValidity(_ value: String) -> Bool? {
            switch self {
            case .string, .anyURI: true
            case .boolean: Lexical.isBoolean(value)
            case .qName, .notation: Lexical.isQName(value)
            case .name: Lexical.isName(value)
            case .ncName: Lexical.isNCName(value)
            case .nmtoken: Lexical.isNMToken(value)
            case .language: Lexical.isLanguage(value)
            default: nil
            }
        }

        private func numericValidity(_ value: String) -> Bool {
            switch self {
            case .decimal: DecimalValue(value, allowFraction: true) != nil
            case .integer: DecimalValue(value, allowFraction: false) != nil
            case .double, .float: Lexical.isFloating(value)
            case .duration: Lexical.isDuration(value)
            case let .dateKind(kind): DateTimeParser.parse(value, kind: kind) != nil
            case .hexBinary: Lexical.isHexBinary(value)
            case .base64Binary: Lexical.isBase64Binary(value)
            default: false
            }
        }

        /// The ordering value for a lexically valid string, or nil for the
        /// unordered spaces.
        func ordered(_ value: String) -> OrderedValue? {
            switch self {
            case .decimal: DecimalValue(value, allowFraction: true).map(OrderedValue.decimal)
            case .integer: DecimalValue(value, allowFraction: false).map(OrderedValue.decimal)
            case .double, .float: Self.floatingValue(value).map(OrderedValue.double)
            case let .dateKind(kind): DateTimeParser.parse(value, kind: kind).map(OrderedValue.dateTime)
            default: nil
            }
        }

        private static func floatingValue(_ value: String) -> Double? {
            switch value {
            case "INF": .infinity
            case "-INF": -.infinity
            case "NaN": .nan
            default: Double(value)
            }
        }

        /// The unit `length`, `minLength`, and `maxLength` count: octets for binary
        /// types, characters otherwise.
        func measuredLength(_ value: String) -> Int {
            switch self {
            case .hexBinary: value.count / 2
            case .base64Binary: Self.base64Octets(value)
            default: value.count
            }
        }

        private static func base64Octets(_ value: String) -> Int {
            let padding = value.reversed().prefix { $0 == "=" }.count
            return value.count / 4 * 3 - padding
        }
    }
}
