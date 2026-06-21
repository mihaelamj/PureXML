private typealias NestedNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// A named `simpleType` or `attributeGroup` definition is a top-level component:
    /// the schema-for-schemas `localSimpleType` and the nested `attributeGroup`
    /// (a reference) forms carry no `name`. A `simpleType` nested inside a
    /// `restriction`/`list`/`union`/`element`/`attribute`, or an `attributeGroup`
    /// nested inside a `complexType`/`attributeGroup`, that declares a `name` was
    /// accepted; it is now rejected. A nested anonymous `simpleType` and an
    /// `attributeGroup` reference (which carry no `name`) are unaffected.
    ///
    /// "Top-level" means a direct child of `schema` or of a `redefine`; everything
    /// deeper is nested.
    static func nestedNamedDefinitionFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        collectNestedNamed(schema, parentIsTopLevel: false, into: &findings)
        return findings
    }

    private static func collectNestedNamed(_ node: XSDTree, parentIsTopLevel: Bool, into findings: inout [PureXML.Schema.SchemaLocatedFinding]) {
        let kind = NestedNode.localName(node)
        // Foreign content inside an annotation is not the schema's own and is not
        // structurally checked.
        if kind == "appinfo" || kind == "documentation" { return }
        if isNestedNamedDefinition(node, kind, parentIsTopLevel: parentIsTopLevel) {
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "a nested '\(kind ?? "")' definition may not have a 'name'; only a top-level definition is named",
                node: node,
            ))
        }
        let childrenAreTopLevel = kind == "schema" || kind == "redefine"
        for child in NestedNode.elementChildren(node) {
            collectNestedNamed(child, parentIsTopLevel: childrenAreTopLevel, into: &findings)
        }
    }

    /// Whether `node` is a nested (non-top-level) `simpleType`/`attributeGroup` in
    /// the XSD namespace that declares a `name` (which only a top-level definition
    /// may carry).
    private static func isNestedNamedDefinition(_ node: XSDTree, _ kind: String?, parentIsTopLevel: Bool) -> Bool {
        !parentIsTopLevel
            && node.name?.namespaceURI == xsdNamespace
            && (kind == "simpleType" || kind == "attributeGroup")
            && hasUnprefixedName(node)
    }

    private static func hasUnprefixedName(_ node: XSDTree) -> Bool {
        node.attributes.contains { $0.name.prefix == nil && $0.name.localName == "name" }
    }
}
