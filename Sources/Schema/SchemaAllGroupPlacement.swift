private typealias AllNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `cos-all-limited.1.2`: an `all` group may only be the whole content
    /// model of a complex type. A direct `all` nested in a `sequence`/`choice` is
    /// already rejected by the child-content table; the remaining case is an `all`
    /// reached through a `<group ref>` to a named group whose content is an `all`,
    /// where that reference appears inside a compositor (so the `all` is not the
    /// whole content). The reference is followed only when it resolves to this
    /// schema's own target namespace.
    static func allGroupReferencePlacementFindings(_ containers: [XSDTree], _ bindings: [String: String], _ target: String?) -> [PureXML.Schema.SchemaLocatedFinding] {
        // A redefined group's effective content is the redefinition's, not the
        // original loaded definition, so a redefined group name is exempt: its
        // original `all` content is overridden (and the suite treats a reference to
        // it inside a compositor as valid).
        var redefined: Set<String> = []
        for container in containers where AllNode.localName(container) == "redefine" {
            for group in AllNode.children(container, named: "group") {
                if let name = AllNode.attribute(group, "name") { redefined.insert(name) }
            }
        }
        var allGroups: Set<String> = []
        for container in containers {
            // A named group defines a component in the target namespace of the
            // schema document that holds it. A reference is only ever followed when
            // it resolves to this schema's own `target` (see `allGroupReference`),
            // so pooling a same-named all-group from an *imported* namespace would
            // wrongly flag a local non-all group referenced inside a compositor.
            // Record only all-groups defined in `target`: a `schema` container's
            // own namespace is its `targetNamespace`; a `redefine` container's
            // redefinitions belong to the including schema (this `target`).
            let containerNamespace = AllNode.localName(container) == "redefine"
                ? target
                : AllNode.attribute(container, "targetNamespace")
            guard containerNamespace == target else { continue }
            for group in descendants(container, named: "group") {
                guard let name = AllNode.attribute(group, "name"), !redefined.contains(name) else { continue }
                if AllNode.elementChildren(group).contains(where: { AllNode.localName($0) == "all" }) {
                    allGroups.insert(name)
                }
            }
        }
        guard !allGroups.isEmpty else { return [] }
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for container in containers {
            collectAllGroupRefPlacement(container, allGroups, bindings, target, into: &findings)
        }
        return findings
    }

    private static func collectAllGroupRefPlacement(
        _ node: XSDTree,
        _ allGroups: Set<String>,
        _ bindings: [String: String],
        _ target: String?,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        let kind = AllNode.localName(node)
        let insideCompositor = kind == "sequence" || kind == "choice" || kind == "all"
        for child in AllNode.elementChildren(node) {
            if insideCompositor, let referenced = allGroupReference(child, allGroups, bindings, target) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "the all-group '\(referenced)' may not be referenced inside a '\(kind ?? "")'; an all group must be the whole content model",
                    node: child,
                ))
            }
            collectAllGroupRefPlacement(child, allGroups, bindings, target, into: &findings)
        }
    }

    /// The name of the all-group `child` references in this schema's target
    /// namespace, or nil when `child` is not such a reference.
    private static func allGroupReference(_ child: XSDTree, _ allGroups: Set<String>, _ bindings: [String: String], _ target: String?) -> String? {
        guard AllNode.localName(child) == "group", let ref = AllNode.attribute(child, "ref"),
              AllNode.referenceNamespace(ref, bindings) == target
        else {
            return nil
        }
        let name = AllNode.stripPrefix(ref)
        return allGroups.contains(name) ? name : nil
    }
}
