private typealias SimpleContentNode = PureXML.Schema.XSDNode
private typealias SimpleContentType = PureXML.Schema.SimpleType
private typealias SimpleContentContext = PureXML.Schema.XSDContext
private typealias SimpleContentBuiltinType = PureXML.Schema.BuiltinType

extension PureXML.Schema.XSDParser {
    static func simpleContentType(
        _ node: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        visited: Set<String> = [],
    ) -> PureXML.Schema.SimpleType {
        guard let inner = derivation(node) else { return SimpleContentType(base: .string) }
        let rawBase = SimpleContentNode.attribute(inner, "base") ?? "string"
        let baseName = SimpleContentNode.stripPrefix(rawBase)
        let bindings = namespaceBindingsInScope(of: inner, defaultBindings: context.namespaceBindings)
        let uri = SimpleContentNode.referenceNamespace(rawBase, bindings)

        let baseType = simpleContentBaseType(baseName, uri: uri, context, visited: visited)
        let effectiveType: SimpleContentType
        let inlineType = SimpleContentNode.localName(inner) == "restriction"
            ? SimpleContentNode.firstChild(inner, named: "simpleType")
            : nil
        if let inline = inlineType {
            effectiveType = scopedSimpleType(inline, context)
        } else {
            effectiveType = baseType
        }
        var facets = effectiveType.facets
        let declaresEnumeration = SimpleContentNode.elementChildren(inner)
            .contains { SimpleContentNode.localName($0) == "enumeration" }
        if SimpleContentNode.localName(inner) == "restriction", declaresEnumeration {
            facets.enumeration = nil
        }
        PureXML.Schema.XSDSimpleParser.applyFacets(inner, into: &facets)
        return SimpleContentType(base: effectiveType.base, facets: facets, variety: effectiveType.variety, isBuiltinList: effectiveType.isBuiltinList)
    }

    static func scopedSimpleType(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType {
        var scoped = context
        scoped.namespaceBindings = namespaceBindingsInScope(of: node, defaultBindings: context.namespaceBindings)
        return PureXML.Schema.XSDSimpleParser.simpleType(node, scoped)
    }

    /// The simple type a `simpleContent` derivation derives from: an XSD built-in, a
    /// named simple type, or, when the base is another complex type with
    /// simpleContent, that type's own resolved simple type. A cycle in the base
    /// chain falls back to `string`.
    private static func simpleContentBaseType(
        _ baseName: String,
        uri: String?,
        _ context: SimpleContentContext,
        visited: Set<String>,
    ) -> SimpleContentType {
        if uri == PureXML.Schema.XSDParser.xsdNamespace {
            return SimpleContentType(base: SimpleContentBuiltinType(rawValue: baseName) ?? .string)
        }
        if let simple = context.simpleTypes[baseName] {
            return simple
        }
        guard !visited.contains(baseName),
              let complexNode = context.complexTypeNodes[baseName],
              let baseSimpleContent = SimpleContentNode.firstChild(complexNode, named: "simpleContent")
        else { return SimpleContentType(base: .string) }
        return simpleContentType(baseSimpleContent, context, visited: visited.union([baseName]))
    }
}
