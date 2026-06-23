private typealias WildExprNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// cos-ct-extends.1.1 / `src-ct.5`: a complexContent extension's {attribute
    /// wildcard} is the wildcard union of the extension's own attribute wildcard and
    /// the base type's (XSD 1.0 §3.4.2). With Errata E1-10 some unions are NOT
    /// expressible -- both `not` namespace-constraint forms exclude absent, so a
    /// union admitting "every namespace except a name, PLUS absent" (rule 5.1.3,
    /// e.g. base `##other` unioned with `##local` and other names) has no single
    /// expressible form, and the schema is invalid. PureXML formerly widened such a
    /// union to `##any` and accepted it (XSTS wildZ013, test328873i).
    ///
    /// The union RESULT for the expressible cases is already computed correctly in
    /// `XSDComplexContent` (so instance validation admits exactly the right
    /// attributes, XSTS wildZ013a/d); this rule reports the not-expressible ones.
    ///
    /// Disclosed under-rejection (deferred): the INTERSECTION not-expressible case
    /// (`src-ct.4` / `src-attribute_group.2`, two `not` forms negating different
    /// namespace names within one type or attribute group) is not flagged here; it
    /// needs no corpus case and is a separate, rarer rule.
    ///
    /// Located on the `extension` node, the component a developer would correct.
    /// Self-contained schemas only (the base must resolve to this document's target
    /// namespace), matching the other derivation rules.
    static func wildcardUnionExpressibilityFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard !skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) else { return [] }
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for content in descendants(schema, named: "complexContent") {
            guard let extensionNode = WildExprNode.firstChild(content, named: "extension"),
                  let base = WildExprNode.attribute(extensionNode, "base"),
                  WildExprNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[WildExprNode.stripPrefix(base)]
            else { continue }
            let ownWildcard = attributeWildcard(under: extensionNode, context)
            if case .notExpressible = PureXML.Schema.Wildcard.union(ownWildcard, complex.attributeWildcard) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "the union of this extension's attribute wildcard with the base type's attribute wildcard is not expressible (src-ct.5)",
                    node: extensionNode,
                ))
            }
        }
        return findings
    }
}
