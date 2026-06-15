private typealias IDVNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `a-props-correct.3` / `e-props-correct.5`: an attribute or element
    /// declaration whose type is or derives from `xs:ID` must not carry a `default`
    /// or `fixed` value constraint. Runs after named simple types are resolved, so a
    /// named user type derived from `xs:ID` is recognized, not only the built-in and
    /// inline forms. Only XSD-namespace declarations are checked; foreign content is
    /// skipped.
    static func idValueConstraintErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext) -> [String] {
        var errors: [String] = []
        collectIDValueConstraintErrors(schema, context, into: &errors)
        return errors
    }

    private static func collectIDValueConstraintErrors(_ node: XSDTree, _ context: PureXML.Schema.XSDContext, into errors: inout [String]) {
        let local = IDVNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if let error = idValueConstraintError(node, context) {
            errors.append(error)
        }
        for child in IDVNode.elementChildren(node) {
            collectIDValueConstraintErrors(child, context, into: &errors)
        }
    }

    private static func idValueConstraintError(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> String? {
        guard node.name?.namespaceURI == xsdNamespace, let kind = IDVNode.localName(node),
              kind == "element" || kind == "attribute",
              let name = IDVNode.attribute(node, "name"),
              IDVNode.attribute(node, "default") != nil || IDVNode.attribute(node, "fixed") != nil,
              isIDDerived(node, context)
        else { return nil }
        return "'\(kind)' '\(name)' must not have a default or fixed value because its type is derived from ID"
    }

    /// Whether the declaration's type is or derives from `xs:ID`. A `type` attribute
    /// is resolved by reference; an inline `simpleType` is ID only when it restricts
    /// an ID-derived base (a list or union is not derived from ID).
    private static func isIDDerived(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> Bool {
        if let typeName = IDVNode.attribute(node, "type") {
            return typeReferenceIsID(typeName, context)
        }
        guard let inline = IDVNode.firstChild(node, named: "simpleType"),
              let restriction = IDVNode.firstChild(inline, named: "restriction"),
              let base = IDVNode.attribute(restriction, "base")
        else {
            return false
        }
        return typeReferenceIsID(base, context)
    }

    /// Whether a type reference resolves to, or derives from, the built-in `xs:ID`.
    /// The reference's namespace is resolved from its prefix: only an `ID` in the
    /// XSD namespace is the built-in; a user type is ID only if it resolves to one
    /// whose base is `xs:ID`; a foreign or unresolved reference is not ID. (Matching
    /// by local name alone would mistake a user type named `ID`, or an imported
    /// `foo:ID`, for the built-in.)
    private static func typeReferenceIsID(_ typeName: String, _ context: PureXML.Schema.XSDContext) -> Bool {
        if IDVNode.referenceNamespace(typeName, context.namespaceBindings) == xsdNamespace {
            return IDVNode.stripPrefix(typeName) == "ID"
        }
        return context.simpleTypes[IDVNode.stripPrefix(typeName)]?.base == .id
    }
}
