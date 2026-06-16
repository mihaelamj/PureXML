extension PureXML.Schema.XSDParser {
    static func mergedNamespaceBindings(on node: XSDTree, inherited: [String: String]) -> [String: String] {
        var bindings = inherited
        for attribute in node.attributes {
            if attribute.name.prefix == "xmlns" {
                bindings[attribute.name.localName] = attribute.value
            } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                bindings[""] = attribute.value
            }
        }
        return bindings
    }

    /// Global component names in loaded containers outside the main target namespace.
    static func foreignComponentPools(
        _ containers: [XSDTree],
        mainTargetNamespace: String?,
    ) -> [String?: [String: Set<String>]] {
        let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: mainTargetNamespace)
        var result: [String?: [String: Set<String>]] = [:]
        for index in containers.indices {
            let container = containers[index]
            guard PureXML.Schema.XSDNode.localName(container) != "redefine" else { continue }
            let namespaceURI = namespaceMap[index] ?? mainTargetNamespace
            if namespacesMatch(namespaceURI, mainTargetNamespace) { continue }
            var pools = result[namespaceURI, default: [:]]
            insertNamedGlobals(from: container, into: &pools)
            result[namespaceURI] = pools
        }
        return result
    }

    private static func insertNamedGlobals(from container: XSDTree, into pools: inout [String: Set<String>]) {
        insertGlobalElements(from: container, into: &pools)
        insertGlobalNames(child: "attribute", pool: "attribute", from: container, into: &pools)
        insertGlobalNames(child: "group", pool: "group", from: container, into: &pools)
        insertGlobalNames(child: "attributeGroup", pool: "attributeGroup", from: container, into: &pools)
        insertGlobalNames(child: "simpleType", pool: "type", from: container, into: &pools)
        insertGlobalNames(child: "complexType", pool: "type", from: container, into: &pools)
    }

    private static func insertGlobalElements(from container: XSDTree, into pools: inout [String: Set<String>]) {
        for element in PureXML.Schema.XSDNode.children(container, named: "element") {
            guard PureXML.Schema.XSDNode.attribute(element, "ref") == nil,
                  let name = PureXML.Schema.XSDNode.attribute(element, "name") else { continue }
            pools["element", default: []].insert(name)
        }
    }

    private static func insertGlobalNames(
        child: String,
        pool: String,
        from container: XSDTree,
        into pools: inout [String: Set<String>],
    ) {
        for node in PureXML.Schema.XSDNode.children(container, named: child) {
            if let name = PureXML.Schema.XSDNode.attribute(node, "name") {
                pools[pool, default: []].insert(name)
            }
        }
    }

    private static func namespacesMatch(_ lhs: String?, _ rhs: String?) -> Bool {
        lhs == rhs || ((lhs == nil || lhs == "") && (rhs == nil || rhs == ""))
    }
}
