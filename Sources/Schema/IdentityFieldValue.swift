/// One field of an identity tuple: its lexical value and the simple type it
/// compares in (from the node's `xsi:type`, if any). Two field values are equal
/// when they denote the same value: in the value space of their type when both
/// share a built-in base (so `3.0` equals `3` for `xsd:decimal`), otherwise by
/// lexical form.
struct FieldValue: Equatable {
    let string: String
    let type: PureXML.Schema.SimpleType?
    let namespaceBindings: [String: String]

    init(string: String, type: PureXML.Schema.SimpleType?, namespaceBindings: [String: String] = [:]) {
        self.string = string
        self.type = type
        self.namespaceBindings = namespaceBindings
    }

    static func == (lhs: FieldValue, rhs: FieldValue) -> Bool {
        if let left = lhs.qnameValue, let right = rhs.qnameValue, left.uri == right.uri, left.local == right.local {
            return true
        }
        if let lhsType = lhs.type, let rhsType = rhs.type {
            if lhsType.base == rhsType.base {
                return lhsType.valueMatches(lhs.string, literal: rhs.string)
            }
            return Self.numericallyEqual(lhs.string, lhsType.base, rhs.string, rhsType.base)
        }
        return lhs.string == rhs.string
    }

    /// Whether two values denote the same number across the decimal-derived
    /// numeric family. `decimal` and the integer types share one value space, so
    /// `1` (decimal) equals `1` (unsignedByte). Distinct primitive spaces (a
    /// number versus a string, or `float`/`double`) are excluded, so they never
    /// compare equal here.
    private static func numericallyEqual(
        _ left: String,
        _ leftBase: PureXML.Schema.BuiltinType,
        _ right: String,
        _ rightBase: PureXML.Schema.BuiltinType,
    ) -> Bool {
        guard leftBase.isDecimalDerived, rightBase.isDecimalDerived,
              let leftValue = PureXML.Schema.DecimalValue(left, allowFraction: true),
              let rightValue = PureXML.Schema.DecimalValue(right, allowFraction: true)
        else { return false }
        return leftValue == rightValue
    }

    private var qnameValue: (uri: String?, local: String)? {
        let trimmed = string.trimmingXMLWhitespace()
        guard trimmed.contains(":") else { return nil }
        let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else { return nil }
        let uri = namespaceBindings[parts[0]] ?? (parts[0].isEmpty ? namespaceBindings[""] : nil)
        return (uri, parts[1])
    }
}
