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
    static func baseComponents(in containers: [XSDTree], named kind: String) -> [String: XSDTree] {
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
    static func resolveBaseComponent(_ base: [String: XSDTree], name: String, owner: XSDTree) -> XSDTree? {
        base[namespacedKey(name, owner: owner)] ?? base["{}\(name)"]
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
