extension PureXML.Schema.XSDParser {
    /// Enforces variety constraints on simpleTypes (XSD 1.0 Datatypes §3.3.1 / §3.4.1):
    /// the itemType of a list must be atomic or union (where all member types are atomic).
    /// That is, a list's itemType cannot be a list or a union containing a list, and
    /// cannot resolve to the simple ur-type 'anySimpleType'.
    static func simpleTypeVarietyErrors(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext) -> [String] {
        let targetNamespace = context.targetNamespace
        var errors: [String] = []

        func check(_ node: XSDTree) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }

            if node.name?.namespaceURI == xsdNamespace, local == "list" {
                let item: PureXML.Schema.SimpleType = if let itemType = PureXML.Schema.XSDNode.attribute(node, "itemType") {
                    PureXML.Schema.XSDSimpleParser.simpleTypeReference(itemType, context)
                } else if let inline = PureXML.Schema.XSDNode.elementChildren(node).first(where: { PureXML.Schema.XSDNode.localName($0) == "simpleType" }) {
                    PureXML.Schema.XSDSimpleParser.simpleType(inline, context)
                } else {
                    PureXML.Schema.SimpleType(base: .string)
                }

                var isForeign = false
                if let itemType = PureXML.Schema.XSDNode.attribute(node, "itemType") {
                    let bindings = inScopeNamespaceBindings(of: node)
                    let prefix = PureXML.Schema.XSDNode.prefix(itemType)
                    let uri = prefix.flatMap { bindings[$0] } ?? bindings[""]
                    if uri != targetNamespace, uri != xsdNamespace, uri != nil, uri != "" {
                        isForeign = true
                    }
                }

                if !isForeign, isListOrUnionContainingList(item) {
                    errors.append("the item type of a list must be atomic or union of atomic, not a list or union containing list")
                }
                // src-simple-type.2: a list has its item type from EITHER the
                // itemType attribute OR an inline simpleType child, never both and
                // never neither.
                if hasItemTypeAttribute(node) == hasSimpleTypeChild(node) {
                    errors.append("a list must have either an 'itemType' attribute or an inline simpleType child, but not both")
                }
            }

            // src-simple-type.3: a union draws its members from a memberTypes
            // attribute, inline simpleType children, or both, so it must declare at
            // least one of them (an empty union has no member type definitions).
            if isEmptyUnion(node, local) {
                errors.append("a union must declare at least one member type, through 'memberTypes' or an inline simpleType child")
            }

            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                check(child)
            }
        }

        check(schema)
        return errors
    }

    /// A `union` element in the schema namespace that declares no member types at
    /// all: neither a `memberTypes` attribute nor an inline `simpleType` child.
    private static func isEmptyUnion(_ node: XSDTree, _ local: String?) -> Bool {
        node.name?.namespaceURI == xsdNamespace && local == "union"
            && PureXML.Schema.XSDNode.attribute(node, "memberTypes") == nil
            && !hasSimpleTypeChild(node)
    }

    private static func hasItemTypeAttribute(_ node: XSDTree) -> Bool {
        PureXML.Schema.XSDNode.attribute(node, "itemType") != nil
    }

    private static func hasSimpleTypeChild(_ node: XSDTree) -> Bool {
        PureXML.Schema.XSDNode.elementChildren(node).contains { PureXML.Schema.XSDNode.localName($0) == "simpleType" }
    }

    private static func inScopeNamespaceBindings(of node: XSDTree) -> [String: String] {
        var bindings: [String: String] = [:]
        var current: XSDTree? = node
        while let element = current {
            for attribute in element.attributes {
                if attribute.name.prefix == "xmlns" {
                    let prefix = attribute.name.localName
                    if bindings[prefix] == nil {
                        bindings[prefix] = attribute.value
                    }
                } else if attribute.name.prefix == nil, attribute.name.localName == "xmlns" {
                    if bindings[""] == nil {
                        bindings[""] = attribute.value
                    }
                }
            }
            current = element.parent
        }
        return bindings
    }

    private static func isListOrUnionContainingList(_ type: PureXML.Schema.SimpleType) -> Bool {
        if type.isAnySimpleType { return true }
        switch type.variety {
        case .list:
            return true
        case let .union(members):
            return members.contains { isListOrUnionContainingList($0) }
        case .atomic:
            return false
        }
    }
}
