private typealias RedefineNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// A redefinition of an `attributeGroup` is a RESTRICTION of the original
    /// (src-redefine / cos-ct-restricts), so it may neither eliminate a REQUIRED
    /// attribute the original declares, nor re-introduce one the original prohibits.
    /// To stay false-positive-free: the drop-required check fires only when the
    /// redefinition declares its attributes directly (no nested `attributeGroup`
    /// reference, which could re-introduce the attribute); the re-introduced-
    /// prohibited check fires only when the original has no attribute wildcard (which
    /// could otherwise admit the attribute).
    static func redefineAttributeGroupRestrictionFindings(_ containers: [XSDTree]) -> [PureXML.Schema.SchemaLocatedFinding] {
        let base = baseComponents(in: containers, named: "attributeGroup")
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for container in containers where RedefineNode.localName(container) == "redefine" {
            for redefinition in RedefineNode.children(container, named: "attributeGroup") {
                guard let name = RedefineNode.attribute(redefinition, "name"),
                      let baseGroup = resolveBaseComponent(base, name: name, owner: redefinition)
                else { continue }
                let referenced = referencedAttributeNames(of: redefinition, ownName: name, base: base)
                // Each restriction violation is a property of this redefinition's
                // attribute group, so it locates on the redefinition declaration.
                findings += attributeGroupRestrictionErrors(name: name, base: baseGroup, redefinition: redefinition, referenced: referenced)
                    .map { PureXML.Schema.SchemaLocatedFinding(reason: $0, node: redefinition) }
            }
        }
        return findings
    }

    /// The non-prohibited attribute names a redefinition pulls in through its
    /// `attributeGroup` references, with whether any is a SELF-reference (resolving by
    /// NAMESPACE and local name to the redefinition's own name+target; reported via
    /// `hasSelfReference` rather than counted, since it re-imports the original). Returns
    /// nil (decline, stay lenient) when the contributed set is not fully known: a
    /// referenced group that does not resolve, carries an attribute wildcard, nests a
    /// further `attributeGroup` reference, or names an attribute by `ref` (not `name`).
    private static func referencedAttributeNames(
        of redefinition: XSDTree, ownName: String, base: [String: XSDTree],
    ) -> (names: Set<String>, hasSelfReference: Bool)? {
        let schema = RedefineNode.schemaOwner(redefinition)
        let target = RedefineNode.attribute(schema, "targetNamespace") ?? ""
        let bindings = RedefineNode.namespaceBindings(of: schema)
        var names: Set<String> = []
        var hasSelfReference = false
        for child in RedefineNode.elementChildren(redefinition) where RedefineNode.localName(child) == "attributeGroup" {
            guard let ref = RedefineNode.attribute(child, "ref") else { return nil }
            let refNamespace = RedefineNode.referenceNamespace(ref, bindings) ?? ""
            if RedefineNode.stripPrefix(ref) == ownName, refNamespace == target {
                hasSelfReference = true
                continue
            }
            guard let group = base["{\(refNamespace)}\(RedefineNode.stripPrefix(ref))"] else { return nil }
            for member in RedefineNode.elementChildren(group) {
                switch RedefineNode.localName(member) {
                case "attribute":
                    guard let attrName = RedefineNode.attribute(member, "name") else { return nil }
                    if RedefineNode.attribute(member, "use") != "prohibited" { names.insert(attrName) }
                case "anyAttribute", "attributeGroup":
                    return nil
                default:
                    break
                }
            }
        }
        return (names, hasSelfReference)
    }

    private static func attributeGroupRestrictionErrors(
        name: String,
        base: XSDTree,
        redefinition: XSDTree,
        referenced: (names: Set<String>, hasSelfReference: Bool)?,
    ) -> [String] {
        var errors: [String] = []
        let children = RedefineNode.elementChildren(redefinition)
        // The redefinition's attributes by name, so a check can read the `use` (a
        // re-declared prohibited attribute kept prohibited is valid) and the `fixed`
        // value (a restriction may not relax the original's fixed constraint).
        var redefined: [String: XSDTree] = [:]
        for attribute in children where RedefineNode.localName(attribute) == "attribute" {
            if let attrName = RedefineNode.attribute(attribute, "name") { redefined[attrName] = attribute }
        }
        let use: (String) -> String? = { redefined[$0].map { RedefineNode.attribute($0, "use") ?? "optional" } }
        let hasReference = children.contains { RedefineNode.localName($0) == "attributeGroup" }
        let baseHasWildcard = RedefineNode.elementChildren(base).contains { RedefineNode.localName($0) == "anyAttribute" }
        // A restriction may not ADD an attribute the original lacks (and the original
        // has no wildcard to admit it). The redefinition's full attribute set is its
        // direct declarations PLUS those pulled in by a NON-self attributeGroup
        // reference (`referenced.names`); a self-reference re-imports the original's own
        // attributes, so declaring further ones alongside it is a valid redefine (W3C
        // attgC007/attgC038/groupB018), not an addition. The check runs only when that
        // set is fully known (`referenced` resolved, no self-reference) and the
        // original's set is fully known (no nested reference, no wildcard), so an
        // inherited attribute is never mistaken for an added one (catches attgC028,
        // whose `ref="car"` injects foreign attributes with no self-reference).
        let baseNames = Set(RedefineNode.children(base, named: "attribute").compactMap { RedefineNode.attribute($0, "name") })
        let baseHasReference = RedefineNode.elementChildren(base).contains { RedefineNode.localName($0) == "attributeGroup" }
        if !baseHasReference, !baseHasWildcard {
            errors += addedAttributeErrors(name: name, redefined: redefined, baseNames: baseNames, referenced: referenced, use: use)
        }
        for attribute in RedefineNode.children(base, named: "attribute") {
            guard let attrName = RedefineNode.attribute(attribute, "name") else { continue }
            // A restriction may not relax a fixed value: if the original fixes an
            // attribute, the redefinition's matching (non-prohibited) attribute must
            // fix it to the same value.
            if relaxesFixedValue(base: attribute, redefined: redefined[attrName], use: use(attrName)) {
                errors.append("a redefined attribute group '\(name)' may not relax the fixed value of '\(attrName)'")
            }
            if use(attrName) != "prohibited", widensBuiltinType(base: attribute, redefined: redefined[attrName]) {
                errors.append("a redefined attribute group '\(name)' may not widen the type of '\(attrName)'")
            }
            if redeclaresSelfSuppliedAttribute(
                attribute,
                redeclaration: redefined[attrName],
                hasSelfReference: referenced?.hasSelfReference == true,
                prohibited: use(attrName) == "prohibited",
            ) {
                errors.append("a redefined attribute group '\(name)' redeclares '\(attrName)', which its self-reference already supplies")
            }
            if let transition = useTransitionError(base: attribute, redefined: redefined[attrName], name: name, hasReference: hasReference, baseHasWildcard: baseHasWildcard) {
                errors.append(transition)
            }
        }
        return errors
    }

    /// The "may not ADD an attribute the original lacks" errors. The redefinition's
    /// full attribute set is its direct (non-prohibited) declarations plus the names a
    /// non-self reference contributes (`referenced.names`, already non-prohibited). A
    /// `use="prohibited"` direct attribute forbids rather than widens, so it is left
    /// alone. The check fires only when both sets are fully known and admit no wildcard:
    /// the original has no nested reference and no wildcard, and the redefinition has a
    /// resolved reference set with no self-reference (a self-reference re-imports the
    /// original and is governed by the restriction rules, not counted as an addition).
    private static func addedAttributeErrors(
        name: String,
        redefined: [String: XSDTree],
        baseNames: Set<String>,
        referenced: (names: Set<String>, hasSelfReference: Bool)?,
        use: (String) -> String?,
    ) -> [String] {
        guard let referenced, !referenced.hasSelfReference else { return [] }
        var effective = referenced.names
        for attrName in redefined.keys where use(attrName) != "prohibited" {
            effective.insert(attrName)
        }
        return effective.sorted().filter { !baseNames.contains($0) }
            .map { "a redefined attribute group '\(name)' may not add the attribute '\($0)'" }
    }

    /// The `use`-transition restriction errors for one base attribute: a redefinition
    /// may not eliminate a REQUIRED attribute (unless a reference could re-supply it),
    /// nor re-introduce a PROHIBITED attribute as usable (unless the original has an
    /// attribute wildcard that could admit it).
    private static func useTransitionError(
        base: XSDTree, redefined: XSDTree?, name: String, hasReference: Bool, baseHasWildcard: Bool,
    ) -> String? {
        guard let attrName = RedefineNode.attribute(base, "name") else { return nil }
        let use = redefined.map { RedefineNode.attribute($0, "use") ?? "optional" }
        switch RedefineNode.attribute(base, "use") {
        case "required" where !hasReference && redefined == nil:
            return "a redefined attribute group '\(name)' may not eliminate the required attribute '\(attrName)'"
        case "prohibited" where !baseHasWildcard && use != nil && use != "prohibited":
            return "a redefined attribute group '\(name)' may not re-introduce the prohibited attribute '\(attrName)'"
        default:
            return nil
        }
    }

    /// schM8 / ag-props-correct.2: when a redefinition SELF-references the original it
    /// re-imports all of the original's attributes, so directly re-declaring one of them
    /// produces two attribute uses of the same name (a duplicate), which is invalid. The
    /// check fires only for a re-declared, NON-prohibited attribute the original directly
    /// declares, and only when BOTH the original and the re-declaration land in NO
    /// namespace (a qualified attribute's target namespace depends on cross-document
    /// `form`/chameleon resolution, so it is not compared, staying lenient).
    private static func redeclaresSelfSuppliedAttribute(
        _ attribute: XSDTree, redeclaration: XSDTree?, hasSelfReference: Bool, prohibited: Bool,
    ) -> Bool {
        guard hasSelfReference, let redeclaration, !prohibited else { return false }
        return isNoNamespaceAttribute(attribute) && isNoNamespaceAttribute(redeclaration)
    }

    /// Whether an attribute use lands in NO namespace: it is not `form="qualified"` and
    /// its owning schema does not set `attributeFormDefault="qualified"`. A qualified
    /// attribute's target namespace depends on cross-document `form`/chameleon
    /// resolution, so the self-reference duplicate check (which compares by local name)
    /// is sound only for no-namespace attributes; a qualified one is not compared.
    private static func isNoNamespaceAttribute(_ attribute: XSDTree) -> Bool {
        if RedefineNode.attribute(attribute, "form") == "qualified" { return false }
        return RedefineNode.attribute(RedefineNode.schemaOwner(attribute), "attributeFormDefault") != "qualified"
    }

    /// Whether a redefined attribute WIDENS the original's type. A redefinition is a
    /// restriction, so a re-declared attribute's type must derive by restriction from
    /// the original's. The check is BUILT-IN-only and therefore certain: it fires only
    /// when both the original and the re-declared attribute name a built-in type and the
    /// re-declared built-in does not derive from the original's in the XSD derivation
    /// lattice (e.g. `int` does not derive from `boolean`, XSTS schM4). A user, inline,
    /// or absent type on either side is not compared (returns false, staying lenient):
    /// an absent original type is `anySimpleType`, which any type validly restricts, and
    /// a user/inline type's derivation is not resolvable here, so no valid restriction
    /// is rejected.
    private static func widensBuiltinType(base: XSDTree, redefined: XSDTree?) -> Bool {
        guard let redefined,
              let baseBuiltin = builtinType(of: base),
              let redefinedBuiltin = builtinType(of: redefined)
        else { return false }
        return !redefinedBuiltin.derives(from: baseBuiltin)
    }

    /// The built-in type an attribute names, ONLY when its `type` QName resolves to the
    /// XSD namespace. A user type whose local name coincides with a built-in (a
    /// `{urn:x}int`) resolves to a different namespace and returns nil, so it is not
    /// mistaken for the built-in and `widensBuiltinType` declines rather than reject a
    /// valid restriction. The QName is resolved against the owning schema's bindings,
    /// the same context `redefineSelfReferenceFindings` uses for redefine references.
    private static func builtinType(of attribute: XSDTree) -> PureXML.Schema.BuiltinType? {
        guard let type = RedefineNode.attribute(attribute, "type") else { return nil }
        let bindings = RedefineNode.namespaceBindings(of: RedefineNode.schemaOwner(attribute))
        guard RedefineNode.referenceNamespace(type, bindings) == xsdNamespace else { return nil }
        return PureXML.Schema.BuiltinType(rawValue: RedefineNode.stripPrefix(type))
    }

    /// A base attribute with a `fixed` value is relaxed when the redefinition declares
    /// a matching, non-prohibited attribute whose `fixed` value differs (or is absent).
    /// Prohibiting or omitting the attribute is not relaxation, so it is left alone.
    private static func relaxesFixedValue(base: XSDTree, redefined: XSDTree?, use: String?) -> Bool {
        guard let fixed = RedefineNode.attribute(base, "fixed"), let redefined, use != "prohibited" else { return false }
        return RedefineNode.attribute(redefined, "fixed") != fixed
    }
}
