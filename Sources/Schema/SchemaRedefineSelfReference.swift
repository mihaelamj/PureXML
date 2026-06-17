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
