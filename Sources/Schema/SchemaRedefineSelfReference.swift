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
    static func redefineSelfReferenceErrors(_ containers: [XSDTree]) -> [String] {
        var errors: [String] = []
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
                                errors.append("a redefined group's self-reference must have minOccurs and maxOccurs of 1")
                            }
                        }
                    }
                    if selfReferences > 1 {
                        errors.append("a redefined \(kind) may contain at most one self-reference")
                    }
                }
            }
        }
        return errors
    }

    /// A redefinition of an `attributeGroup` is a RESTRICTION of the original
    /// (src-redefine / cos-ct-restricts), so it may neither eliminate a REQUIRED
    /// attribute the original declares, nor re-introduce one the original prohibits.
    /// To stay false-positive-free: the drop-required check fires only when the
    /// redefinition declares its attributes directly (no nested `attributeGroup`
    /// reference, which could re-introduce the attribute); the re-introduced-
    /// prohibited check fires only when the original has no attribute wildcard (which
    /// could otherwise admit the attribute).
    static func redefineAttributeGroupRestrictionErrors(_ containers: [XSDTree]) -> [String] {
        // Key the base by NAMESPACED identity: an attribute group is identified by
        // {name, target namespace}, and a redefinition's base is in the redefining
        // schema's own target namespace, so a same-local-name group imported from a
        // different namespace must not be mistaken for the base (matching the
        // namespace guard `redefineSelfReferenceErrors` already uses).
        var base: [String: XSDTree] = [:]
        for container in containers where RedefineNode.localName(container) != "redefine" {
            for group in RedefineNode.children(container, named: "attributeGroup") {
                if let name = RedefineNode.attribute(group, "name") { base[namespacedKey(name, owner: group)] = group }
            }
        }
        var errors: [String] = []
        for container in containers where RedefineNode.localName(container) == "redefine" {
            for redefinition in RedefineNode.children(container, named: "attributeGroup") {
                guard let name = RedefineNode.attribute(redefinition, "name"),
                      let baseGroup = base[namespacedKey(name, owner: redefinition)]
                else { continue }
                errors += attributeGroupRestrictionErrors(name: name, base: baseGroup, redefinition: redefinition)
            }
        }
        return errors
    }

    /// The `{target-namespace}name` identity of a named component, keyed by its
    /// owning schema's `targetNamespace` so same-local-name components in different
    /// namespaces stay distinct.
    private static func namespacedKey(_ name: String, owner node: XSDTree) -> String {
        let target = RedefineNode.attribute(RedefineNode.schemaOwner(node), "targetNamespace") ?? ""
        return "{\(target)}\(name)"
    }

    private static func attributeGroupRestrictionErrors(name: String, base: XSDTree, redefinition: XSDTree) -> [String] {
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
        for attribute in RedefineNode.children(base, named: "attribute") {
            guard let attrName = RedefineNode.attribute(attribute, "name") else { continue }
            // A restriction may not relax a fixed value: if the original fixes an
            // attribute, the redefinition's matching (non-prohibited) attribute must
            // fix it to the same value.
            if relaxesFixedValue(base: attribute, redefined: redefined[attrName], use: use(attrName)) {
                errors.append("a redefined attribute group '\(name)' may not relax the fixed value of '\(attrName)'")
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

    /// A base attribute with a `fixed` value is relaxed when the redefinition declares
    /// a matching, non-prohibited attribute whose `fixed` value differs (or is absent).
    /// Prohibiting or omitting the attribute is not relaxation, so it is left alone.
    private static func relaxesFixedValue(base: XSDTree, redefined: XSDTree?, use: String?) -> Bool {
        guard let fixed = RedefineNode.attribute(base, "fixed"), let redefined, use != "prohibited" else { return false }
        return RedefineNode.attribute(redefined, "fixed") != fixed
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
