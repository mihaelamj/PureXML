public extension PureXML.Schema {
    /// Whitespace processing applied before a value is validated.
    enum WhiteSpace: Sendable {
        case preserve
        case replace
        case collapse
    }

    /// A built-in XSD datatype. Each carries its primitive value space, its
    /// intrinsic `whiteSpace`, and, for the bounded integer types, its inclusive
    /// bounds, exactly as XSD Part 2 derives them.
    enum BuiltinType: String, Sendable, CaseIterable {
        case string
        case normalizedString
        case token
        case language
        case name = "Name"
        case ncName = "NCName"
        case nmtoken = "NMTOKEN"
        case id = "ID"
        case idref = "IDREF"
        case entity = "ENTITY"
        case boolean
        case decimal
        case integer
        case long
        case int
        case short
        case byte
        case nonNegativeInteger
        case positiveInteger
        case nonPositiveInteger
        case negativeInteger
        case unsignedLong
        case unsignedInt
        case unsignedShort
        case unsignedByte
        case float
        case double
        case duration
        case dateTime
        case date
        case time
        case gYearMonth
        case gYear
        case gMonthDay
        case gDay
        case gMonth
        case hexBinary
        case base64Binary
        case anyURI
        case qName = "QName"

        var whiteSpace: WhiteSpace {
            switch self {
            case .string: .preserve
            case .normalizedString: .replace
            default: .collapse
            }
        }

        var primitive: Primitive {
            if let primitive = Self.stringLike[self] { return primitive }
            if Self.integerLike.contains(self) { return .integer }
            return computedPrimitive
        }

        private var computedPrimitive: Primitive {
            switch self {
            case .boolean: .boolean
            case .decimal: .decimal
            case .float: .float
            case .double: .double
            case .duration: .duration
            case .dateTime: .dateKind(.dateTime)
            case .date: .dateKind(.date)
            case .time: .dateKind(.time)
            case .gYearMonth: .dateKind(.gYearMonth)
            case .gYear: .dateKind(.gYear)
            case .gMonthDay: .dateKind(.gMonthDay)
            case .gDay: .dateKind(.gDay)
            case .gMonth: .dateKind(.gMonth)
            case .hexBinary: .hexBinary
            case .base64Binary: .base64Binary
            case .anyURI: .anyURI
            case .qName: .qName
            default: .string
            }
        }

        private static let stringLike: [BuiltinType: Primitive] = [
            .string: .string, .normalizedString: .string, .token: .string,
            .language: .language, .name: .name,
            .ncName: .ncName, .id: .ncName, .idref: .ncName, .entity: .ncName,
            .nmtoken: .nmtoken,
        ]

        private static let integerLike: Set<BuiltinType> = [
            .integer, .long, .int, .short, .byte,
            .nonNegativeInteger, .positiveInteger, .nonPositiveInteger, .negativeInteger,
            .unsignedLong, .unsignedInt, .unsignedShort, .unsignedByte,
        ]

        /// The intrinsic inclusive bounds of the bounded integer types.
        var bounds: (lower: DecimalValue?, upper: DecimalValue?) {
            switch self {
            case .long: (Self.bound("-9223372036854775808"), Self.bound("9223372036854775807"))
            case .int: (Self.bound("-2147483648"), Self.bound("2147483647"))
            case .short: (Self.bound("-32768"), Self.bound("32767"))
            case .byte: (Self.bound("-128"), Self.bound("127"))
            case .unsignedLong: (Self.bound("0"), Self.bound("18446744073709551615"))
            case .unsignedInt: (Self.bound("0"), Self.bound("4294967295"))
            case .unsignedShort: (Self.bound("0"), Self.bound("65535"))
            case .unsignedByte: (Self.bound("0"), Self.bound("255"))
            case .nonNegativeInteger: (Self.bound("0"), nil)
            case .positiveInteger: (Self.bound("1"), nil)
            case .nonPositiveInteger: (nil, Self.bound("0"))
            case .negativeInteger: (nil, Self.bound("-1"))
            default: (nil, nil)
            }
        }

        private static func bound(_ lexical: String) -> DecimalValue? {
            DecimalValue(lexical, allowFraction: false)
        }
    }
}
