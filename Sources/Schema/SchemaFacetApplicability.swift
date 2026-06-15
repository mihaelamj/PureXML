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
    static func simpleTypeVarietyFacetErrors(_ schema: XSDTree) -> [String] {
        let bindings = namespaceBindings(schema)
        let target = PureXML.Schema.XSDNode.attribute(schema, "targetNamespace")
        var errors: [String] = []
        forEachSimpleType(schema) { simpleType in
            guard let restriction = PureXML.Schema.XSDNode.firstChild(simpleType, named: "restriction"),
                  let variety = restrictionBaseVariety(restriction, schema, bindings, target, [])
            else { return }
            let allowed = variety == "list" ? listFacets : unionFacets
            let used = PureXML.Schema.XSDNode.elementChildren(restriction)
                .compactMap(PureXML.Schema.XSDNode.localName)
                .filter { facetNames.contains($0) }
            for facet in used where !allowed.contains(facet) {
                errors.append("the facet '\(facet)' does not apply to a \(variety) type")
            }
        }
        return errors
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
    static func valueConstraintErrors(_ schema: XSDTree) -> [String] {
        let bindings = namespaceBindings(schema)
        var errors: [String] = []
        forEachValueConstrained(schema) { node in
            // The value constraint attributes are the unprefixed, no-namespace
            // `default`/`fixed` on an XSD-namespace declaration; a foreign same-local
            // attribute is not the value constraint and is not structurally checked.
            if hasBothValueConstraints(node) {
                errors.append("a '\(PureXML.Schema.XSDNode.localName(node) ?? "")' declaration may not have both a 'default' and a 'fixed' value constraint")
                return
            }
            if hasDefaultWithNonOptionalUse(node) {
                errors.append("an 'attribute' with a 'default' value constraint must have use='optional'")
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
            errors.append("the \(fixed != nil ? "fixed" : "default") value '\(value)' is not valid for type '\(typeName)'")
        }
        return errors
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
}
