private typealias XSDNode = PureXML.Schema.XSDNode
private typealias SimpleType = PureXML.Schema.SimpleType
private typealias XSDContext = PureXML.Schema.XSDContext
private typealias BuiltinType = PureXML.Schema.BuiltinType
private typealias Facets = PureXML.Schema.Facets

extension PureXML.Schema.XSDSimpleParser {
    /// The canonical digit string of a lexical `nonNegativeInteger` (optional
    /// leading `+`, ASCII digits, surrounding whitespace tolerated), with the
    /// sign and leading zeros stripped (`"0"` for zero), or nil when the lexical
    /// is not one (`-1`, ``, `a`, `1e2`). Independent of machine-integer range,
    /// so a huge but well-formed value is canonicalized, not misreported as
    /// malformed; the canonical form orders two values by length then lexically.
    static func canonicalNonNegativeInteger(_ lexical: String) -> String? {
        var digits = Substring(lexical.trimmingXMLWhitespace())
        if digits.first == "+" { digits = digits.dropFirst() }
        guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
        let trimmed = digits.drop { $0 == "0" }
        return trimmed.isEmpty ? "0" : String(trimmed)
    }

    /// Whether canonical nonNegativeInteger `lhs` is greater than `rhs`: a longer
    /// digit string is larger, and same-length strings compare lexicographically.
    static func greater(_ lhs: String, than rhs: String) -> Bool {
        lhs.count != rhs.count ? lhs.count > rhs.count : lhs > rhs
    }

    static func simpleTypeReference(_ typeName: String, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType {
        let local = XSDNode.stripPrefix(typeName)
        let uri = XSDNode.referenceNamespace(typeName, context.namespaceBindings)

        if uri == PureXML.Schema.XSDParser.xsdNamespace {
            if local == "anySimpleType" { return PureXML.Schema.SimpleType(base: .string, isAnySimpleType: true) }
            if let builtin = PureXML.Schema.BuiltinType(rawValue: local) { return PureXML.Schema.SimpleType(base: builtin) }
            if let item = listBuiltinItem(local) { return .list(item: PureXML.Schema.SimpleType(base: item), isBuiltinList: true) }
        }
        return context.simpleTypes[local] ?? PureXML.Schema.SimpleType(base: .string)
    }

    /// The item type of a built-in list datatype (`IDREFS`, `ENTITIES`,
    /// `NMTOKENS`), each a whitespace-separated list of its singular form.
    static func listBuiltinItem(_ name: String) -> PureXML.Schema.BuiltinType? {
        switch name {
        case "IDREFS": .idref
        case "ENTITIES": .entity
        case "NMTOKENS": .nmtoken
        default: nil
        }
    }

    static func applyFacets(_ restriction: XSDTree, into facets: inout PureXML.Schema.Facets) {
        for facet in XSDNode.elementChildren(restriction) {
            guard facet.name?.namespaceURI == PureXML.Schema.XSDParser.xsdNamespace else { continue }
            let value = XSDNode.attribute(facet, "value")
            applyStringFacet(XSDNode.localName(facet), value, into: &facets)
            applyNumericFacet(XSDNode.localName(facet), value, into: &facets)
        }
    }

    static func listType(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType {
        let item: PureXML.Schema.SimpleType = if let itemType = XSDNode.attribute(node, "itemType") {
            simpleTypeReference(itemType, context)
        } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
            simpleType(inline, context)
        } else {
            PureXML.Schema.SimpleType(base: .string)
        }
        return .list(item: item)
    }

    static func unionType(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType {
        var members: [PureXML.Schema.SimpleType] = []
        if let names = XSDNode.attribute(node, "memberTypes") {
            members += names.split(whereSeparator: { $0.isWhitespace }).map { simpleTypeReference(String($0), context) }
        }
        members += XSDNode.children(node, named: "simpleType").map { simpleType($0, context) }
        return .union(members)
    }

    private static func applyStringFacet(_ name: String?, _ value: String?, into facets: inout PureXML.Schema.Facets) {
        switch name {
        case "pattern": if let value { facets.patterns.append(value) }
        case "enumeration": if let value { facets.enumeration = (facets.enumeration ?? []) + [value] }
        case "minInclusive": facets.minInclusive = value
        case "maxInclusive": facets.maxInclusive = value
        case "minExclusive": facets.minExclusive = value
        case "maxExclusive": facets.maxExclusive = value
        case "whiteSpace": facets.whiteSpace = whiteSpace(value)
        default: break
        }
    }

    private static func applyNumericFacet(_ name: String?, _ value: String?, into facets: inout PureXML.Schema.Facets) {
        let number = value.flatMap(Int.init)
        switch name {
        case "length": facets.length = number
        case "minLength": facets.minLength = number
        case "maxLength": facets.maxLength = number
        case "totalDigits": facets.totalDigits = number
        case "fractionDigits": facets.fractionDigits = number
        default: break
        }
    }

    static func whiteSpace(_ value: String?) -> PureXML.Schema.WhiteSpace? {
        switch value {
        case "preserve": .preserve
        case "replace": .replace
        case "collapse": .collapse
        default: nil
        }
    }
}
