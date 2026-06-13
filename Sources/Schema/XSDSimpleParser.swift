extension PureXML.Schema {
    /// Parses XSD simple types: atomic restrictions with the full facet set, and
    /// the `list` and `union` varieties. Kept beside ``XSDParser``, sharing its
    /// module-scope tree helpers and parsing context.
    enum XSDSimpleParser {
        static func simpleType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            if let list = XSDNode.firstChild(node, named: "list") {
                return listType(list, context)
            }
            if let union = XSDNode.firstChild(node, named: "union") {
                return unionType(union, context)
            }
            guard let restriction = XSDNode.firstChild(node, named: "restriction") else {
                return SimpleType(base: .string)
            }
            // Resolve the base through simpleTypeReference so the built-in list
            // datatypes (NMTOKENS, IDREFS, ENTITIES) keep their list variety: a
            // length facet on one of them counts list items, not characters (#146).
            // Restricting a user type inherits its base, facets, and variety.
            let baseType = simpleTypeReference(XSDNode.attribute(restriction, "base") ?? "string", context)
            var facets = baseType.facets
            applyFacets(restriction, into: &facets)
            return SimpleType(base: baseType.base, facets: facets, variety: baseType.variety)
        }

        static func simpleTypeReference(_ typeName: String, _ context: XSDContext) -> SimpleType {
            let local = XSDNode.stripPrefix(typeName)
            if let builtin = BuiltinType(rawValue: local) { return SimpleType(base: builtin) }
            if let item = listBuiltinItem(local) { return .list(item: SimpleType(base: item)) }
            return context.simpleTypes[local] ?? SimpleType(base: .string)
        }

        /// The item type of a built-in list datatype (`IDREFS`, `ENTITIES`,
        /// `NMTOKENS`), each a whitespace-separated list of its singular form.
        static func listBuiltinItem(_ name: String) -> BuiltinType? {
            switch name {
            case "IDREFS": .idref
            case "ENTITIES": .entity
            case "NMTOKENS": .nmtoken
            default: nil
            }
        }

        static func applyFacets(_ restriction: XSDTree, into facets: inout Facets) {
            for facet in XSDNode.elementChildren(restriction) {
                let value = XSDNode.attribute(facet, "value")
                applyStringFacet(XSDNode.localName(facet), value, into: &facets)
                applyNumericFacet(XSDNode.localName(facet), value, into: &facets)
            }
        }

        private static func listType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            let item: SimpleType = if let itemType = XSDNode.attribute(node, "itemType") {
                simpleTypeReference(itemType, context)
            } else if let inline = XSDNode.firstChild(node, named: "simpleType") {
                simpleType(inline, context)
            } else {
                SimpleType(base: .string)
            }
            return .list(item: item)
        }

        private static func unionType(_ node: XSDTree, _ context: XSDContext) -> SimpleType {
            var members: [SimpleType] = []
            if let names = XSDNode.attribute(node, "memberTypes") {
                members += names.split(whereSeparator: \.isWhitespace).map { simpleTypeReference(String($0), context) }
            }
            members += XSDNode.children(node, named: "simpleType").map { simpleType($0, context) }
            return .union(members)
        }

        private static func applyStringFacet(_ name: String?, _ value: String?, into facets: inout Facets) {
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

        private static func applyNumericFacet(_ name: String?, _ value: String?, into facets: inout Facets) {
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

        private static func whiteSpace(_ value: String?) -> WhiteSpace? {
            switch value {
            case "preserve": .preserve
            case "replace": .replace
            case "collapse": .collapse
            default: nil
            }
        }
    }
}
