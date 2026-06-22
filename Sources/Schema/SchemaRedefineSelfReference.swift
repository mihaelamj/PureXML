private typealias RedefineNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// src-redefine.6.1.1/6.1.2 (group) and 7.2.1 (attributeGroup): a `group` or
    /// `attributeGroup` inside `xs:redefine` may reference ITSELF (the component it
    /// redefines) AT MOST ONCE, and a group self-reference must have
    /// `minOccurs` = `maxOccurs` = 1. Two self-references, or a group self-reference
    /// with any other occurrence (`minOccurs="0"`, `maxOccurs="unbounded"`, a count
    /// above 1), is invalid. A reference is the self-reference only when it resolves
    /// (by NAMESPACE, not local name alone) to the redefined component: a
    /// `<group ref="b:g">` to an imported component sharing the local name is a
    /// different component and is unconstrained, so the namespace guard prevents a
    /// false positive. (`attributeGroup` references carry no occurrence.) The walk is
    /// BOUNDED: it stops at `element`/`complexType` scopes, so a recursive reference
    /// inside a nested element's content (a data-structure recursion) is not
    /// miscounted as a redefinition self-reference.
    static func redefineSelfReferenceFindings(_ containers: [XSDTree]) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for container in containers where RedefineNode.localName(container) == "redefine" {
            let schema = RedefineNode.schemaOwner(container)
            let target = RedefineNode.attribute(schema, "targetNamespace")
            let bindings = RedefineNode.namespaceBindings(of: schema)
            for kind in ["group", "attributeGroup"] {
                for definition in RedefineNode.children(container, named: kind) {
                    guard let name = RedefineNode.attribute(definition, "name") else { continue }
                    var selfReferences = 0
                    for ref in boundedSelfReferenceNodes(definition, kind) {
                        guard let refName = RedefineNode.attribute(ref, "ref"),
                              RedefineNode.stripPrefix(refName) == name,
                              RedefineNode.referenceNamespace(refName, bindings) == target
                        else { continue }
                        selfReferences += 1
                        if kind == "group" {
                            let minOccurs = RedefineNode.attribute(ref, "minOccurs") ?? "1"
                            let maxOccurs = RedefineNode.attribute(ref, "maxOccurs") ?? "1"
                            if maxOccurs == "unbounded" || canonicalMagnitude(minOccurs) != "1" || canonicalMagnitude(maxOccurs) != "1" {
                                findings.append(PureXML.Schema.SchemaLocatedFinding(
                                    reason: "a redefined group's self-reference must have minOccurs and maxOccurs of 1",
                                    node: ref,
                                ))
                            }
                        }
                    }
                    if selfReferences > 1 {
                        findings.append(PureXML.Schema.SchemaLocatedFinding(
                            reason: "a redefined \(kind) may contain at most one self-reference",
                            node: definition,
                        ))
                    }
                }
            }
        }
        return findings
    }

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

    /// The `{target-namespace}name` identity of a named component, keyed by its
    /// owning schema's `targetNamespace` so same-local-name components in different
    /// namespaces stay distinct.
    private static func namespacedKey(_ name: String, owner node: XSDTree) -> String {
        let target = RedefineNode.attribute(RedefineNode.schemaOwner(node), "targetNamespace") ?? ""
        return "{\(target)}\(name)"
    }

    /// Named components of `kind` declared directly in the non-redefine containers,
    /// keyed by namespaced identity: an attribute group or model group is identified by
    /// {name, target namespace}, so a same-local-name component imported from a
    /// different namespace is not mistaken for the redefinition's base (the namespace
    /// guard `redefineSelfReferenceFindings` already uses). This is the pool a
    /// redefinition's base is drawn from.
    private static func baseComponents(in containers: [XSDTree], named kind: String) -> [String: XSDTree] {
        var base: [String: XSDTree] = [:]
        for container in containers where RedefineNode.localName(container) != "redefine" {
            for component in RedefineNode.children(container, named: kind) {
                if let name = RedefineNode.attribute(component, "name") { base[namespacedKey(name, owner: component)] = component }
            }
        }
        return base
    }

    /// The base component a redefinition redefines: looked up by namespaced identity,
    /// then by the chameleon `{}name` key, since a redefined schema with no
    /// `targetNamespace` is absorbed into the redefining schema's namespace. A base in a
    /// DIFFERENT explicit namespace keys under neither, so no cross-namespace component
    /// is mistaken for the original.
    private static func resolveBaseComponent(_ base: [String: XSDTree], name: String, owner: XSDTree) -> XSDTree? {
        base[namespacedKey(name, owner: owner)] ?? base["{}\(name)"]
    }

    /// The non-prohibited attribute names a redefinition pulls in through its
    /// `attributeGroup` references, with whether any of them is a SELF-reference
    /// (resolving by NAMESPACE and local name to the redefinition's own name+target).
    /// A self-reference re-imports the original and is reported via `hasSelfReference`
    /// rather than counted. Returns nil (decline, stay lenient) when a referenced
    /// group does not resolve from the base pool, carries an attribute wildcard, nests
    /// a further `attributeGroup` reference, or names an attribute by `ref` (not
    /// `name`): in each case the contributed set is not fully known, so the add-check
    /// must not fire. A redefinition with no `attributeGroup` reference yields an empty
    /// set and no self-reference, preserving the direct-declaration-only behavior.
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
            switch RedefineNode.attribute(attribute, "use") {
            case "required" where !hasReference && redefined[attrName] == nil:
                errors.append("a redefined attribute group '\(name)' may not eliminate the required attribute '\(attrName)'")
            case "prohibited" where !baseHasWildcard && use(attrName) != nil && use(attrName) != "prohibited":
                errors.append("a redefined attribute group '\(name)' may not re-introduce the prohibited attribute '\(attrName)'")
            default:
                break
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

    /// cos-group-restrict: a model group redefined inside `xs:redefine` is a
    /// RESTRICTION of the group it redefines, so its content model must accept a
    /// subset of the original's. The check reuses the same particle-restriction
    /// oracle as complex-type restriction (`ParticleRestriction.violation`). To stay
    /// false-positive-free it runs only when the original group resolves by namespaced
    /// identity and when the redefinition has NO self-reference (a `<group ref>` to its
    /// own name expands to the original and is governed by the self-reference
    /// well-formedness rule instead, and cannot be re-parsed reliably here). An
    /// order-independent `all` reordering accepts the same language, so the oracle
    /// correctly does not flag it; only a genuine content widening is reported.
    static func redefineGroupRestrictionFindings(
        _ containers: [XSDTree],
        context: PureXML.Schema.XSDContext,
        types: [String: PureXML.Schema.ElementType],
        derivation: [String: PureXML.Schema.TypeDerivation],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        let base = baseComponents(in: containers, named: "group")
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for container in containers where RedefineNode.localName(container) == "redefine" {
            for redefinition in RedefineNode.children(container, named: "group") {
                guard let name = RedefineNode.attribute(redefinition, "name"),
                      !hasGroupSelfReference(redefinition, name: name),
                      let original = resolveBaseComponent(base, name: name, owner: redefinition),
                      let redefined = modelGroup(in: redefinition, context),
                      let baseline = modelGroup(in: original, context),
                      // A `maxOccurs=0` ("pointless") member in the original puts the
                      // redefine into contested cos-group-restrict territory (the spec's
                      // normalization removes it, yet XSTS accepts a redefinition that
                      // re-enables that very member, e.g. mgO013). Decline to judge such
                      // a base rather than risk over-rejecting a valid redefine; this
                      // only withholds a rejection, so it cannot introduce a false positive.
                      !hasPointlessParticle(baseline)
                else { continue }
                if let reason = PureXML.Schema.ParticleRestriction.violation(
                    restricted: .elementOnly(redefined), base: .elementOnly(baseline), types: types, derivation: derivation,
                ) {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "a redefined model group '\(name)' must restrict the group it redefines: \(reason)",
                        node: redefinition,
                    ))
                }
            }
        }
        return findings
    }

    /// Whether `particle` or any of its descendants can never occur (`maxOccurs=0`), a
    /// "pointless particle" whose normalization in the redefine-restriction check is
    /// contested.
    private static func hasPointlessParticle(_ particle: PureXML.Schema.Particle) -> Bool {
        if particle.maxOccurs == 0 { return true }
        if case let .group(group) = particle.term { return group.particles.contains(where: hasPointlessParticle) }
        return false
    }

    /// Whether a redefinition group contains a self-reference (`<group ref>` to its own
    /// name within its bounded model), which expands to the original and is handled by
    /// the self-reference well-formedness rule rather than re-parsed here.
    private static func hasGroupSelfReference(_ redefinition: XSDTree, name: String) -> Bool {
        boundedSelfReferenceNodes(redefinition, "group").contains { ref in
            RedefineNode.attribute(ref, "ref").map(RedefineNode.stripPrefix) == name
        }
    }

    /// The reference NODES of `kind` nested directly in `node`'s model, stopping at
    /// `element`/`complexType`/`simpleType`/`attribute` scopes so a reference inside a
    /// nested element's content (a data-structure recursion, not a redefinition
    /// self-reference) is excluded.
    private static func boundedSelfReferenceNodes(_ node: XSDTree, _ kind: String) -> [XSDTree] {
        var nodes: [XSDTree] = []
        for child in RedefineNode.elementChildren(node) {
            switch RedefineNode.localName(child) {
            case "element", "complexType", "simpleType", "attribute":
                continue
            case kind:
                if RedefineNode.attribute(child, "ref") != nil { nodes.append(child) }
            default:
                nodes += boundedSelfReferenceNodes(child, kind)
            }
        }
        return nodes
    }
}
