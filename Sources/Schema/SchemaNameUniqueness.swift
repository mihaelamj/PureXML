extension PureXML.Schema.XSDParser {
    /// Schema-validity findings for component-name uniqueness. Within a schema,
    /// global type names (simpleType and complexType share one symbol space),
    /// global element names, global attribute names, named model-group names, and
    /// named attribute-group names must each be unique; identity-constraint names
    /// (unique/key/keyref) must be unique across the whole schema. A duplicate was
    /// accepted, with a later definition silently overwriting the earlier one.
    ///
    /// Only the document's own globals are examined (`xs:redefine` children and
    /// included documents are not direct globals here), so a redefinition is not
    /// mistaken for a clash.
    static func componentNameErrors(_ schema: XSDTree, _ containers: [XSDTree], _ mainTargetNamespace: String?) -> [String] {
        let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: mainTargetNamespace)
        let uniqueIndices = findUniqueIndices(in: containers, namespaceMap: namespaceMap, mainTargetNamespace: mainTargetNamespace)

        var errors = checkDuplicateGlobals(
            in: containers,
            indices: uniqueIndices,
            namespaceMap: namespaceMap,
            mainTargetNamespace: mainTargetNamespace,
        )
        errors += identityConstraintNameErrors(
            containers,
            uniqueIndices,
            namespaceMap: namespaceMap,
            mainTargetNamespace: mainTargetNamespace,
        )
        errors += keyrefReferErrors(schema)
        return errors
    }

    private static func findUniqueIndices(
        in containers: [XSDTree],
        namespaceMap: [Int: String?],
        mainTargetNamespace: String?,
    ) -> [Int] {
        var uniqueIndices: [Int] = []
        for index in containers.indices {
            let container = containers[index]
            let namespaceURI = namespaceMap[index] ?? mainTargetNamespace
            let alreadyExists = uniqueIndices.contains { prevIndex in
                let prevNS = namespaceMap[prevIndex] ?? mainTargetNamespace
                return prevNS == namespaceURI && isStructurallyEqual(containers[prevIndex], container)
            }
            if !alreadyExists {
                uniqueIndices.append(index)
            }
        }
        return uniqueIndices
    }

    private struct ComponentKey: Hashable {
        let kind: String
        let targetNamespace: String?
        let name: String
    }

    private static func checkDuplicateGlobals(
        in containers: [XSDTree],
        indices: [Int],
        namespaceMap: [Int: String?],
        mainTargetNamespace: String?,
    ) -> [String] {
        var errors: [String] = []
        var seenComponents: Set<ComponentKey> = []
        for index in indices {
            let container = containers[index]
            guard PureXML.Schema.XSDNode.localName(container) != "redefine" else { continue }
            let namespaceURI = namespaceMap[index] ?? mainTargetNamespace
            let globals = PureXML.Schema.XSDNode.elementChildren(container).filter {
                $0.name?.namespaceURI == xsdNamespace
            }
            for global in globals {
                let localName = PureXML.Schema.XSDNode.localName(global) ?? ""
                guard let kind = componentKind(for: localName),
                      let name = PureXML.Schema.XSDNode.attribute(global, "name")?.trimmingXMLWhitespace()
                else {
                    continue
                }
                let key = ComponentKey(kind: kind, targetNamespace: namespaceURI, name: name)
                if !seenComponents.insert(key).inserted {
                    let nsStr = namespaceURI.map { " in namespace '\($0)'" } ?? " in no namespace"
                    let kindLabel = kind == "group" ? "model group" : (kind == "attributeGroup" ? "attribute group" : kind)
                    errors.append("duplicate \(kindLabel) name '\(name)'\(nsStr)")
                }
            }
        }
        return errors
    }

    private static func componentKind(for localName: String) -> String? {
        switch localName {
        case "simpleType", "complexType": "type"
        case "element": "element"
        case "attribute": "attribute"
        case "group": "group"
        case "attributeGroup": "attributeGroup"
        default: nil
        }
    }

    private struct KeyrefInfo {
        let name: String
        let refer: String
        let arity: Int
    }

    /// Findings for a `keyref` whose `refer` does not name a `key` or `unique` in
    /// the document, or whose field arity does not match the referenced key/unique's.
    /// Skipped when the document pulls in external definitions
    /// (`import`/`include`/`redefine`), which the default compile does not load,
    /// so a `refer` into them is never flagged.
    private static func keyrefReferErrors(_ schema: XSDTree) -> [String] {
        if hasExternalReference(schema) { return [] }
        var keyArities: [String: Int] = [:]
        var keyrefs: [KeyrefInfo] = []
        collectKeysAndRefers(schema, keyArities: &keyArities, keyrefs: &keyrefs)

        var errors: [String] = []
        for keyref in keyrefs {
            if let keyArity = keyArities[keyref.refer] {
                if keyArity != keyref.arity {
                    errors.append("keyref '\(keyref.name)' and its referenced key/unique '\(keyref.refer)' must have the same number of fields")
                }
            } else {
                errors.append("keyref refers to undeclared key or unique '\(keyref.refer)'")
            }
        }
        return errors
    }

    private static func collectKeysAndRefers(
        _ node: XSDTree,
        keyArities: inout [String: Int],
        keyrefs: inout [KeyrefInfo],
    ) {
        if let local = PureXML.Schema.XSDNode.localName(node), local == "appinfo" || local == "documentation" { return }
        if node.name?.namespaceURI == xsdNamespace, let local = PureXML.Schema.XSDNode.localName(node) {
            if local == "key" || local == "unique", let name = PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace() {
                let arity = PureXML.Schema.XSDNode.elementChildren(node)
                    .count(where: { $0.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName($0) == "field" })

                keyArities[name] = arity
            }
            if local == "keyref" {
                let name = PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace()
                let refer = PureXML.Schema.XSDNode.attribute(node, "refer")?.trimmingXMLWhitespace()
                if let name, let refer {
                    let arity = PureXML.Schema.XSDNode.elementChildren(node)
                        .count(where: { $0.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName($0) == "field" })
                    keyrefs.append(KeyrefInfo(name: name, refer: PureXML.Schema.XSDNode.stripPrefix(refer), arity: arity))
                }
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectKeysAndRefers(child, keyArities: &keyArities, keyrefs: &keyrefs)
        }
    }

    private static func identityConstraintNameErrors(
        _ containers: [XSDTree],
        _ uniqueIndices: [Int],
        namespaceMap: [Int: String?],
        mainTargetNamespace: String?,
    ) -> [String] {
        struct KeyrefNameKey: Hashable {
            let targetNamespace: String?
            let name: String
        }
        var seen: Set<KeyrefNameKey> = []
        var errors: [String] = []
        func walk(_ node: XSDTree, namespaceURI: String?) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }
            if let name = identityConstraintName(node) {
                let key = KeyrefNameKey(targetNamespace: namespaceURI, name: name)
                if !seen.insert(key).inserted {
                    let nsStr = namespaceURI.map { " in namespace '\($0)'" } ?? " in no namespace"
                    errors.append("duplicate identity constraint name '\(name)'\(nsStr)")
                }
            }
            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                walk(child, namespaceURI: namespaceURI)
            }
        }
        for index in uniqueIndices {
            let container = containers[index]
            guard PureXML.Schema.XSDNode.localName(container) != "redefine" else { continue }
            let namespaceURI = namespaceMap[index] ?? mainTargetNamespace
            walk(container, namespaceURI: namespaceURI)
        }
        return errors
    }

    /// The `name` of `node` when it is an identity constraint (`unique`/`key`/
    /// `keyref`) in the XSD namespace, or nil.
    private static func identityConstraintName(_ node: XSDTree) -> String? {
        guard node.name?.namespaceURI == xsdNamespace,
              let local = PureXML.Schema.XSDNode.localName(node),
              ["unique", "key", "keyref"].contains(local)
        else { return nil }
        return PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace()
    }

    private static func isStructurallyEqual(_ lhs: XSDTree, _ rhs: XSDTree) -> Bool {
        if lhs.name != rhs.name { return false }
        if lhs.attributes.count != rhs.attributes.count { return false }
        for attr in lhs.attributes {
            guard let rhsVal = rhs.attributes.first(where: { $0.name == attr.name })?.value,
                  rhsVal == attr.value
            else { return false }
        }
        let lhsChildren = PureXML.Schema.XSDNode.elementChildren(lhs)
        let rhsChildren = PureXML.Schema.XSDNode.elementChildren(rhs)
        if lhsChildren.count != rhsChildren.count { return false }
        guard !zip(lhsChildren, rhsChildren).contains(where: { !isStructurallyEqual($0, $1) }) else { return false }
        return true
    }

    private static func resolveContainerNamespaces(_ containers: [XSDTree], mainTargetNamespace: String?) -> [Int: String?] {
        var resolved: [Int: String?] = [:]
        guard !containers.isEmpty else { return resolved }
        let mainIndex = containers.count - 1
        resolved[mainIndex] = mainTargetNamespace
        for parentIndex in containers.indices.reversed() {
            guard let parentNamespace = resolved[parentIndex] else { continue }
            let parent = containers[parentIndex]
            for child in PureXML.Schema.XSDNode.elementChildren(parent) {
                let kind = PureXML.Schema.XSDNode.localName(child)
                guard kind == "include" || kind == "import" || kind == "redefine",
                      let childKind = kind
                else {
                    continue
                }
                let targetNamespaceURI: String? = if childKind == "import" {
                    PureXML.Schema.XSDNode.attribute(child, "namespace")
                } else {
                    parentNamespace
                }
                let expectedAttrNamespace: String? = childKind == "import" ? PureXML.Schema.XSDNode.attribute(child, "namespace") : parentNamespace
                let foundIndex = findMatchingContainerIndex(
                    in: containers,
                    before: parentIndex,
                    kind: childKind,
                    namespaces: (parent: parentNamespace, expected: expectedAttrNamespace),
                    resolved: resolved,
                )
                if let foundIndex {
                    resolved[foundIndex] = targetNamespaceURI
                }
            }
        }
        for index in containers.indices where resolved[index] == nil {
            let container = containers[index]
            if let attrNS = PureXML.Schema.XSDNode.attribute(container, "targetNamespace") {
                resolved[index] = attrNS
            } else {
                resolved[index] = mainTargetNamespace
            }
        }
        return resolved
    }

    private static func findMatchingContainerIndex(
        in containers: [XSDTree],
        before parentIndex: Int,
        kind: String,
        namespaces: (parent: String?, expected: String?),
        resolved: [Int: String?],
    ) -> Int? {
        for index in (0 ..< parentIndex).reversed() where resolved[index] == nil {
            let container = containers[index]
            let attrNS = PureXML.Schema.XSDNode.attribute(container, "targetNamespace")
            let isMatch: Bool = if kind == "import" {
                attrNS == namespaces.expected
            } else {
                attrNS == nil || attrNS == namespaces.parent
            }
            if isMatch {
                return index
            }
        }
        return nil
    }
}
