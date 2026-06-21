extension PureXML.Schema.ContentModelDeterminism {
    /// The model-group node (`sequence`/`choice`/`all`/`group`) that holds a
    /// complex type's content model, reached through `complexContent` and its
    /// `restriction`/`extension`, or nil for simple or empty content.
    static func contentModelNode(_ complexType: XSDTree) -> XSDTree? {
        if let direct = modelGroupChild(complexType) { return direct }
        guard let complexContent = PureXML.Schema.XSDNode.firstChild(complexType, named: "complexContent") else { return nil }
        for derivation in PureXML.Schema.XSDNode.elementChildren(complexContent) {
            if let model = modelGroupChild(derivation) { return model }
        }
        return nil
    }

    private static func modelGroupChild(_ node: XSDTree) -> XSDTree? {
        PureXML.Schema.XSDNode.elementChildren(node).first {
            ["sequence", "choice", "all", "group"].contains(PureXML.Schema.XSDNode.localName($0) ?? "")
        }
    }

    /// The ordered model-group nodes whose concatenation is a complex type's
    /// EFFECTIVE content model. For a `complexContent` extension this is the
    /// base type's effective content followed by this type's own content (XSD
    /// 1.0 3.4.2: a content type derived by extension is the base content type's
    /// particle followed by the extension's). A `restriction` or the shorthand
    /// form contributes only its own content. The base is followed only when it
    /// resolves to a local (target-namespace) complex type whose chain is
    /// non-cyclic; a foreign, built-in (e.g. `xs:anyType`), unresolved, or cyclic
    /// base cannot be assembled here, so the cross-boundary check stands down to
    /// this type's own content, never rejecting a model it cannot fully see (an
    /// under-rejection, never a false positive).
    static func effectiveModelNodes(
        _ complexType: XSDTree,
        _ bindings: [String: String],
        _ context: PureXML.Schema.XSDContext,
        _ visiting: Set<String>,
    ) -> [XSDTree] {
        let own = contentModelNode(complexType).map { [$0] } ?? []
        guard let base = extensionBaseName(complexType),
              PureXML.Schema.XSDNode.referenceNamespace(base, bindings) == context.targetNamespace
        else {
            return own
        }
        let baseName = PureXML.Schema.XSDNode.stripPrefix(base)
        guard !visiting.contains(baseName), let baseNode = context.complexTypeNodes[baseName] else {
            return own
        }
        return effectiveModelNodes(baseNode, bindings, context, visiting.union([baseName])) + own
    }

    /// The `base` of a `complexContent` extension, or nil when the type is not a
    /// complexContent extension (a restriction or the shorthand form).
    private static func extensionBaseName(_ complexType: XSDTree) -> String? {
        guard let content = PureXML.Schema.XSDNode.firstChild(complexType, named: "complexContent"),
              let ext = PureXML.Schema.XSDNode.firstChild(content, named: "extension")
        else {
            return nil
        }
        return PureXML.Schema.XSDNode.attribute(ext, "base")
    }
}
