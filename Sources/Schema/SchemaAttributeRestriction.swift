private typealias AttrRestrictNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 Derivation Valid (Restriction, Complex) for attribute uses
    /// (`cos-ct-derived-ok` / `derivation-ok-restriction.2`): when a complex type
    /// restricts a base, an attribute the restriction redeclares may not relax the
    /// base's corresponding use. A base `required` attribute must stay required: it
    /// may not become optional or prohibited. Such schemas were accepted.
    ///
    /// Only attributes the restriction explicitly declares that also exist in the
    /// base are checked; an attribute the restriction omits is inherited unchanged
    /// (valid), and an attribute with no base counterpart is a separate rule, left
    /// alone. Checked for a self-contained schema (no `import`/`include`/`redefine`),
    /// where the base resolves locally and attribute names are unambiguous; the base
    /// reference must resolve to this schema's own target namespace.
    ///
    /// Disclosed under-rejection: the matching fixed-value clause (a base attribute
    /// fixed to a value must keep that value) is not enforced here. It requires
    /// comparing the two fixed values in the attribute type's value space, not
    /// lexically (e.g. a list type's `"1   2  3"` and `"1 2 3"` are the same value),
    /// which a string comparison gets wrong; that clause is left for a later change.
    static func attributeRestrictionErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext, _ types: [String: PureXML.Schema.ElementType]) -> [String] {
        guard !hasExternalReference(schema) else { return [] }
        let bindings = context.namespaceBindings
        var errors: [String] = []
        for content in descendants(schema, named: "complexContent") {
            guard let restriction = AttrRestrictNode.firstChild(content, named: "restriction"),
                  let base = AttrRestrictNode.attribute(restriction, "base"),
                  AttrRestrictNode.referenceNamespace(base, bindings) == context.targetNamespace,
                  case let .complex(complex)? = types[AttrRestrictNode.stripPrefix(base)]
            else { continue }
            for derived in attributeUses(under: restriction, context) {
                if let message = attributeRestrictionViolation(derived, complex.attributes) {
                    errors.append(message)
                }
            }
        }
        return errors
    }

    /// The way `derived` (an attribute the restriction redeclares) illegally relaxes
    /// its base counterpart, or nil when it is a valid restriction of it (or has no
    /// base counterpart). A base `required` attribute may not be made optional or
    /// prohibited (a prohibited use has `required == false`).
    private static func attributeRestrictionViolation(_ derived: PureXML.Schema.AttributeUse, _ baseAttributes: [PureXML.Schema.AttributeUse]) -> String? {
        guard let base = baseAttributes.first(where: { $0.name == derived.name }) else { return nil }
        if base.required, !derived.required {
            return "attribute '\(derived.name.localName)' is required in the base type and a restriction may not make it optional or prohibited"
        }
        return nil
    }
}
