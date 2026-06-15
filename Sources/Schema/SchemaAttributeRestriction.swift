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
                if let message = attributeRestrictionViolation(derived, complex.attributes, restriction, context) {
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
    /// Also checks that fixed attributes keep their fixed values.
    private static func attributeRestrictionViolation(
        _ derived: PureXML.Schema.AttributeUse,
        _ baseAttributes: [PureXML.Schema.AttributeUse],
        _ restrictionNode: XSDTree,
        _ context: PureXML.Schema.XSDContext,
    ) -> String? {
        guard let base = baseAttributes.first(where: { $0.name == derived.name }) else { return nil }
        if base.required, !derived.required {
            return "attribute '\(derived.name.localName)' is required in the base type and a restriction may not make it optional or prohibited"
        }
        if isProhibited(derived.name, under: restrictionNode, context) {
            return nil
        }
        if !isSimpleTypeRestrictionOK(derived: derived.type, base: base.type) {
            return "attribute '\(derived.name.localName)' has type '\(derived.type.base.rawValue)' which is not a valid restriction of base type '\(base.type.base.rawValue)'"
        }
        if let baseFixed = base.valueConstraint?.fixedValue {
            guard let derivedConstraint = derived.valueConstraint,
                  let derivedFixed = derivedConstraint.fixedValue
            else {
                return "attribute '\(derived.name.localName)' is fixed in the base type and a restriction must also make it fixed"
            }
            if !derived.type.valueMatches(derivedFixed, literal: baseFixed) {
                return "attribute '\(derived.name.localName)' has fixed value '\(derivedFixed)' which does not match base fixed value '\(baseFixed)' in the type's value space"
            }
        }
        return nil
    }

    static func isSimpleTypeRestrictionOK(derived: PureXML.Schema.SimpleType, base: PureXML.Schema.SimpleType) -> Bool {
        if base.isAnySimpleType {
            return true
        }
        if derived.isAnySimpleType {
            return false
        }
        switch (derived.variety, base.variety) {
        case (.atomic, .atomic):
            return derived.base.derives(from: base.base)
        case let (.list(derivedItem), .list(baseItem)):
            return isSimpleTypeRestrictionOK(derived: derivedItem, base: baseItem)
        case (.union, .union):
            guard case let .union(derivedMembers) = derived.variety,
                  case let .union(baseMembers) = base.variety
            else { return false }
            return derivedMembers.allSatisfy { derivedMember in
                baseMembers.contains { baseMember in
                    isSimpleTypeRestrictionOK(derived: derivedMember, base: baseMember)
                }
            }
        case (_, .union):
            guard case let .union(baseMembers) = base.variety else { return false }
            return baseMembers.contains { baseMember in
                isSimpleTypeRestrictionOK(derived: derived, base: baseMember)
            }
        default:
            return false
        }
    }

    private static func isProhibited(_ name: PureXML.Model.QualifiedName, under node: XSDTree, _ context: PureXML.Schema.XSDContext, visited: Set<String> = []) -> Bool {
        for child in AttrRestrictNode.elementChildren(node) {
            switch AttrRestrictNode.localName(child) {
            case "attribute":
                if let attrName = attributeName(child, context), attrName == name {
                    if AttrRestrictNode.attribute(child, "use") == "prohibited" {
                        return true
                    }
                }
            case "attributeGroup":
                guard let ref = AttrRestrictNode.attribute(child, "ref") else { break }
                let refName = AttrRestrictNode.stripPrefix(ref)
                guard !visited.contains(refName), let group = context.attributeGroups[refName] else { break }
                if isProhibited(name, under: group, context, visited: visited.union([refName])) {
                    return true
                }
            default:
                break
            }
        }
        return false
    }

    private static func attributeName(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Model.QualifiedName? {
        if let ref = AttrRestrictNode.attribute(node, "ref") {
            let refName = AttrRestrictNode.stripPrefix(ref)
            return PureXML.Model.QualifiedName(localName: refName, namespaceURI: context.targetNamespace)
        }
        guard let name = AttrRestrictNode.attribute(node, "name") else { return nil }
        let qualified = AttrRestrictNode.attribute(node, "form") == "qualified"
            || (AttrRestrictNode.attribute(node, "form") == nil && context.attributeFormQualified)
        return PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil)
    }
}
