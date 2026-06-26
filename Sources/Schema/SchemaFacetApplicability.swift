extension PureXML.Schema.XSDParser {
    /// Facet applicability to a simple type's variety (XSD 1.0 Part 2, 4.3): a
    /// `list` may be constrained only by `length`/`minLength`/`maxLength`,
    /// `pattern`, `enumeration`, and `whiteSpace`; a `union` only by `pattern` and
    /// `enumeration`. A value-bound facet (`maxInclusive`, `totalDigits`, ...)
    /// constrains an atomic value space, not a list or union, so restricting a list
    /// by `maxInclusive` was wrongly accepted (the stF families).
    ///
    /// The base's variety is resolved from the raw tree, since this runs before the
    /// types are compiled; an atomic, unresolvable, or external base is skipped, so
    /// no valid restriction is rejected.
    static func simpleTypeVarietyFacetFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        let bindings = namespaceBindings(schema)
        let target = PureXML.Schema.XSDNode.attribute(schema, "targetNamespace")
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachSimpleType(schema) { simpleType in
            guard let restriction = PureXML.Schema.XSDNode.firstChild(simpleType, named: "restriction"),
                  let variety = restrictionBaseVariety(restriction, schema, bindings, target, [])
            else { return }
            let allowed = variety == "list" ? listFacets : unionFacets
            let used = PureXML.Schema.XSDNode.elementChildren(restriction)
                .compactMap(PureXML.Schema.XSDNode.localName)
                .filter { facetNames.contains($0) }
            for facet in used where !allowed.contains(facet) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "the facet '\(facet)' does not apply to a \(variety) type",
                    node: simpleType,
                ))
            }
        }
        return findings
    }

    /// A `default`/`fixed` value on an `element` or `attribute` must be a valid value
    /// of its `type` (Attribute/Element Locally Valid, XSD 1.0); the two are
    /// mutually exclusive (`src-element.1` / `src-attribute.1`: `default` and `fixed`
    /// must not both be present); and an `attribute` carrying a `default` must have
    /// `use="optional"` (`src-attribute.2`). Only a type that resolves to a built-in datatype is
    /// value-checked, since the check runs before the types are compiled; a
    /// `fixed="abc"` on an `xs:integer` was wrongly accepted. A named or inline user
    /// type, or a type in another namespace, is left alone, so no valid value
    /// constraint is rejected.
    static func valueConstraintFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        let bindings = namespaceBindings(schema)
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachValueConstrained(schema) { node in
            // The value constraint attributes are the unprefixed, no-namespace
            // `default`/`fixed` on an XSD-namespace declaration; a foreign same-local
            // attribute is not the value constraint and is not structurally checked.
            if hasBothValueConstraints(node) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "a '\(PureXML.Schema.XSDNode.localName(node) ?? "")' declaration may not have both a 'default' and a 'fixed' value constraint",
                    node: node,
                ))
                return
            }
            if hasDefaultWithNonOptionalUse(node) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "an 'attribute' with a 'default' value constraint must have use='optional'",
                    node: node,
                ))
                return
            }
            guard let typeName = PureXML.Schema.XSDNode.attribute(node, "type") else { return }
            let fixed = PureXML.Schema.XSDNode.attribute(node, "fixed")
            guard let value = fixed ?? PureXML.Schema.XSDNode.attribute(node, "default") else { return }
            let (prefix, local) = splitQName(typeName)
            let uri = prefix.map { bindings[$0] } ?? bindings[""]
            guard uri == xsdNamespace, let builtin = PureXML.Schema.BuiltinType(rawValue: local),
                  !PureXML.Schema.SimpleType(base: builtin).isValid(value)
            else { return }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "the \(fixed != nil ? "fixed" : "default") value '\(value)' is not valid for type '\(typeName)'",
                node: node,
            ))
        }
        return findings
    }

    /// A `default`/`fixed` value on an `element` or `attribute` whose `type` names a
    /// user-declared type in this schema's own target namespace must be a valid value
    /// of that type (Element/Attribute Locally Valid, `e-props-correct.2` /
    /// `a-props-correct.2`). This runs after the named types are compiled, so it
    /// complements the built-in-only structure-time check: a `fixed="false"` on a
    /// type restricting `xs:boolean` by `pattern="true"`, or a `default="Yes"` on a
    /// complex type whose simple content extends `xs:boolean`, is now rejected.
    ///
    /// The type name is resolved namespace-aware; only a type in the schema's own
    /// target namespace (looked up in the compiled `types`) is checked. A built-in
    /// (handled at structure time), an imported or otherwise foreign type, or an
    /// inline anonymous type is left alone, so no valid value constraint is rejected.
    /// The compiled `SimpleType` validator is the same one instance validation uses,
    /// so its whitespace and facet handling match.
    static func userTypeValueConstraintFindings(
        _ schema: XSDTree,
        _ context: PureXML.Schema.XSDContext,
        _ types: [String: PureXML.Schema.ElementType],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        let bindings = context.namespaceBindings
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachValueConstrained(schema) { node in
            guard node.name?.namespaceURI == xsdNamespace,
                  let typeName = unprefixedValue(node, "type")
            else { return }
            let fixed = unprefixedValue(node, "fixed")
            guard let value = fixed ?? unprefixedValue(node, "default") else { return }
            let (prefix, local) = splitQName(typeName)
            let uri = prefix.map { bindings[$0] } ?? bindings[""]
            guard uri == context.targetNamespace, let resolved = types[local],
                  let simple = simpleContentType(of: resolved), !simple.isValid(value)
            else { return }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "the \(fixed != nil ? "fixed" : "default") value '\(value)' is not valid for type '\(typeName)'",
                node: node,
            ))
        }
        return findings
    }

    /// Like ``userTypeValueConstraintFindings`` but for an element or attribute whose
    /// type is INLINE (no `type` attribute): an inline `simpleType`, or an inline
    /// complex type with `simpleContent`. The `default`/`fixed` value must be valid
    /// against that type's value space. Validated against the simpleContent base's
    /// value space (not the local restriction facets), so only a clear value-space
    /// mismatch (a non-numeric `default` on a decimal-based type) is flagged.
    static func inlineTypeValueConstraintFindings(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachValueConstrained(schema) { node in
            guard node.name?.namespaceURI == xsdNamespace,
                  unprefixedValue(node, "type") == nil
            else { return }
            let fixed = unprefixedValue(node, "fixed")
            guard let value = fixed ?? unprefixedValue(node, "default"),
                  let simple = inlineSimpleType(of: node, context), !simple.isValid(value)
            else { return }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "the \(fixed != nil ? "fixed" : "default") value '\(value)' is not valid for the declared inline type",
                node: node,
            ))
        }
        return findings
    }

    /// The simple value space of an element/attribute's INLINE type: an inline
    /// `simpleType` child, or an inline complex type whose `simpleContent` derives
    /// from a base simple type. Anything else (element-only/mixed/empty content)
    /// carries no simple value space here and is left unchecked.
    private static func inlineSimpleType(of node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.SimpleType? {
        if let inline = PureXML.Schema.XSDNode.firstChild(node, named: "simpleType") {
            return PureXML.Schema.XSDSimpleParser.simpleType(inline, context)
        }
        guard let complexType = PureXML.Schema.XSDNode.firstChild(node, named: "complexType"),
              let simpleContent = PureXML.Schema.XSDNode.firstChild(complexType, named: "simpleContent"),
              let derivation = PureXML.Schema.XSDNode.firstChild(simpleContent, named: "extension")
              ?? PureXML.Schema.XSDNode.firstChild(simpleContent, named: "restriction"),
              let base = PureXML.Schema.XSDNode.attribute(derivation, "base")
        else { return nil }
        return PureXML.Schema.XSDSimpleParser.simpleTypeReference(base, context)
    }

    /// The simple type a value constraint is validated against: a simple type
    /// directly, or the simple content of a complex type. A complex type with
    /// element-only, mixed, or empty content carries no simple value space here, so
    /// it is not value-checked (a disclosed under-rejection).
    private static func simpleContentType(of type: PureXML.Schema.ElementType) -> PureXML.Schema.SimpleType? {
        switch type {
        case let .simple(simple):
            return simple
        case let .complex(complex):
            if case let .simpleContent(simple) = complex.content { return simple }
            return nil
        case .typeReference:
            return nil
        }
    }

    private static func forEachValueConstrained(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if local == "element" || local == "attribute" { visit(node) }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            forEachValueConstrained(child, visit)
        }
    }

    /// The value of the unprefixed (no-namespace) attribute named `local`, or nil.
    private static func unprefixedValue(_ node: XSDTree, _ local: String) -> String? {
        node.attributes.first { $0.name.prefix == nil && $0.name.localName == local }?.value
    }

    /// Whether `node` carries the unprefixed (no-namespace) attribute named `local`.
    private static func hasUnprefixedAttribute(_ node: XSDTree, _ local: String) -> Bool {
        unprefixedValue(node, local) != nil
    }

    /// Whether an XSD-namespace declaration carries both a `default` and a `fixed`
    /// value constraint, which `src-element.1` / `src-attribute.1` forbid.
    private static func hasBothValueConstraints(_ node: XSDTree) -> Bool {
        node.name?.namespaceURI == xsdNamespace
            && hasUnprefixedAttribute(node, "default")
            && hasUnprefixedAttribute(node, "fixed")
    }

    /// Whether an XSD-namespace `attribute` use carries a `default` together with a
    /// `use` other than `optional`, which `src-attribute.2` forbids: a default value
    /// makes the attribute optional, so `use="required"` or `use="prohibited"` is a
    /// contradiction.
    private static func hasDefaultWithNonOptionalUse(_ node: XSDTree) -> Bool {
        guard node.name?.namespaceURI == xsdNamespace,
              PureXML.Schema.XSDNode.localName(node) == "attribute",
              hasUnprefixedAttribute(node, "default"),
              let use = unprefixedValue(node, "use")
        else { return false }
        return use == "required" || use == "prohibited"
    }

    private static let facetNames: Set<String> = [
        "minExclusive", "minInclusive", "maxExclusive", "maxInclusive", "totalDigits",
        "fractionDigits", "length", "minLength", "maxLength", "enumeration", "whiteSpace", "pattern",
    ]
    private static let listFacets: Set<String> = ["length", "minLength", "maxLength", "pattern", "enumeration", "whiteSpace"]
    private static let unionFacets: Set<String> = ["pattern", "enumeration"]
    private static let builtinListTypes: Set<String> = ["IDREFS", "ENTITIES", "NMTOKENS"]

    private static func forEachSimpleType(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if local == "simpleType" { visit(node) }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            forEachSimpleType(child, visit)
        }
    }

    /// The variety (`"list"`, `"union"`, or nil for atomic/unknown) a `restriction`
    /// derives from: an inline `simpleType` base wins, otherwise the `base` QName.
    private static func restrictionBaseVariety(_ restriction: XSDTree, _ schema: XSDTree, _ bindings: [String: String], _ target: String?, _ visited: Set<String>) -> String? {
        if let inlineBase = PureXML.Schema.XSDNode.firstChild(restriction, named: "simpleType") {
            return simpleTypeVariety(inlineBase, schema, bindings, target, visited)
        }
        guard let base = PureXML.Schema.XSDNode.attribute(restriction, "base") else { return nil }
        return namedTypeVariety(base, schema, bindings, target, visited)
    }

    private static func simpleTypeVariety(_ simpleType: XSDTree, _ schema: XSDTree, _ bindings: [String: String], _ target: String?, _ visited: Set<String>) -> String? {
        if PureXML.Schema.XSDNode.firstChild(simpleType, named: "list") != nil { return "list" }
        if PureXML.Schema.XSDNode.firstChild(simpleType, named: "union") != nil { return "union" }
        if let restriction = PureXML.Schema.XSDNode.firstChild(simpleType, named: "restriction") {
            return restrictionBaseVariety(restriction, schema, bindings, target, visited)
        }
        return nil
    }

    /// The variety of a named base, resolved namespace-aware so a same-local-name
    /// collision never flips the variety: a base in the XSD namespace is a built-in
    /// (only the list datatypes are list-variety; the rest atomic, nil); a base in
    /// the schema's own target namespace resolves to a declared global `simpleType`
    /// (cycle-guarded); a base in any other namespace is external and skipped (nil).
    private static func namedTypeVariety(_ base: String, _ schema: XSDTree, _ bindings: [String: String], _ target: String?, _ visited: Set<String>) -> String? {
        let (prefix, local) = splitQName(base)
        let uri = prefix.map { bindings[$0] } ?? bindings[""]
        if uri == xsdNamespace {
            return builtinListTypes.contains(local) ? "list" : nil
        }
        guard uri == target, !visited.contains(local), let declared = globalSimpleType(named: local, schema) else { return nil }
        return simpleTypeVariety(declared, schema, bindings, target, visited.union([local]))
    }

    private static func splitQName(_ value: String) -> (prefix: String?, local: String) {
        let parts = value.split(separator: ":", maxSplits: 1).map(String.init)
        return parts.count == 2 ? (parts[0], parts[1]) : (nil, value)
    }

    private static func globalSimpleType(named name: String, _ schema: XSDTree) -> XSDTree? {
        PureXML.Schema.XSDNode.elementChildren(schema).first {
            PureXML.Schema.XSDNode.localName($0) == "simpleType" && PureXML.Schema.XSDNode.attribute($0, "name") == name
        }
    }

    /// The prefix-to-namespace bindings on the schema element (its `xmlns:prefix`
    /// attributes; the default namespace under the empty key).
    private static func namespaceBindings(_ schema: XSDTree) -> [String: String] {
        var bindings: [String: String] = [:]
        for attribute in schema.attributes {
            if attribute.name.prefix == "xmlns" {
                bindings[attribute.name.localName] = attribute.value
            } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                bindings[""] = attribute.value
            }
        }
        return bindings
    }

    /// Reject any restriction (in the XSD namespace) whose `base`
    /// attribute resolves to `xs:anySimpleType` in the XSD namespace when defined directly under a simpleType.
    static func anySimpleTypeRestrictionFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        let targetNamespace = schema.attributes.first { $0.name.prefix == nil && $0.name.localName == "targetNamespace" }?.value ?? ""
        if targetNamespace == xsdNamespace {
            return []
        }
        let bindings = namespaceBindings(schema)
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachRestrictionInSimpleType(schema) { node in
            guard let base = PureXML.Schema.XSDNode.attribute(node, "base") else { return }
            let (prefix, local) = splitQName(base)
            let uri = prefix.map { bindings[$0] } ?? bindings[""]
            if uri == xsdNamespace, local == "anySimpleType" {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "derivation by restriction of 'xs:anySimpleType' is not allowed",
                    node: node,
                ))
            }
        }
        return findings
    }

    private static func forEachRestrictionInSimpleType(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if node.name?.namespaceURI == xsdNamespace, local == "simpleType" {
            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                if child.name?.namespaceURI == xsdNamespace, PureXML.Schema.XSDNode.localName(child) == "restriction" {
                    visit(child)
                }
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            forEachRestrictionInSimpleType(child, visit)
        }
    }

    /// A constraining facet may not be applied where a `simpleContent` restriction's
    /// base chain resolves to `xs:anySimpleType`, the ur simple type, which carries no
    /// constraining facets (XSD Part 2 §3.2.1): e.g. a complex type extending
    /// `xs:anySimpleType`, restricted by another adding `minLength`. The chain is
    /// followed through local complex types' own simpleContent bases; a base that is a
    /// built-in other than anySimpleType, a simple-type, or external/unresolved is left
    /// alone, so no valid facet is rejected. A restriction supplying its own nested
    /// `simpleType` base is also skipped (the facet applies to that, not anySimpleType).
    static func anySimpleTypeFacetFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        let bindings = namespaceBindings(schema)
        let target = PureXML.Schema.XSDNode.attribute(schema, "targetNamespace")
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        forEachSimpleContentRestriction(schema) { restriction in
            guard PureXML.Schema.XSDNode.firstChild(restriction, named: "simpleType") == nil,
                  let base = PureXML.Schema.XSDNode.attribute(restriction, "base"),
                  hasConstrainingFacet(restriction),
                  simpleContentBaseIsAnySimpleType(base, schema, bindings, target, [])
            else { return }
            findings.append(PureXML.Schema.SchemaLocatedFinding(
                reason: "a constraining facet may not be applied to anySimpleType-based simpleContent",
                node: restriction,
            ))
        }
        return findings
    }

    private static func hasConstrainingFacet(_ restriction: XSDTree) -> Bool {
        PureXML.Schema.XSDNode.elementChildren(restriction)
            .compactMap(PureXML.Schema.XSDNode.localName)
            .contains { facetNames.contains($0) }
    }

    /// Whether the `simpleContent` `base` chain bottoms at `xs:anySimpleType`. Follows a
    /// base naming a local complex type's `simpleContent` to that type's own base;
    /// stops (false) at any other built-in, a simple-type base, or an unresolved one.
    private static func simpleContentBaseIsAnySimpleType(
        _ base: String, _ schema: XSDTree, _ bindings: [String: String], _ target: String?, _ visited: Set<String>,
    ) -> Bool {
        let (prefix, local) = splitQName(base)
        let uri = prefix.map { bindings[$0] } ?? bindings[""]
        if uri == xsdNamespace { return local == "anySimpleType" }
        guard uri == target, !visited.contains(local),
              let complexType = globalComplexType(named: local, schema),
              let simpleContent = PureXML.Schema.XSDNode.firstChild(complexType, named: "simpleContent"),
              let derivation = PureXML.Schema.XSDNode.firstChild(simpleContent, named: "extension")
              ?? PureXML.Schema.XSDNode.firstChild(simpleContent, named: "restriction"),
              let baseRef = PureXML.Schema.XSDNode.attribute(derivation, "base")
        else { return false }
        return simpleContentBaseIsAnySimpleType(baseRef, schema, bindings, target, visited.union([local]))
    }

    private static func globalComplexType(named name: String, _ schema: XSDTree) -> XSDTree? {
        PureXML.Schema.XSDNode.elementChildren(schema).first {
            PureXML.Schema.XSDNode.localName($0) == "complexType" && PureXML.Schema.XSDNode.attribute($0, "name") == name
        }
    }

    private static func forEachSimpleContentRestriction(_ node: XSDTree, _ visit: (XSDTree) -> Void) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if local == "simpleContent", let restriction = PureXML.Schema.XSDNode.firstChild(node, named: "restriction") {
            visit(restriction)
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            forEachSimpleContentRestriction(child, visit)
        }
    }
}
