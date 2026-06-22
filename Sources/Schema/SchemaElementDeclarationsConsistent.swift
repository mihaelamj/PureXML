extension PureXML.Schema.XSDParser {
    /// Findings for Element Declarations Consistent (cos-element-consistent): in a
    /// single complex type's content model, two element declarations with the same
    /// name must have the same type. Collects element particles across the content
    /// model (descending through model groups and content-derivation wrappers, not
    /// into a nested type), keyed by name; a name seen with more than one distinct
    /// type definition is a violation. (Substitution-group expansion is not folded
    /// in, an accepted under-rejection.)
    static func elementDeclsConsistentErrors(_ complexType: XSDTree) -> [String] {
        var byName: [String: Set<String>] = [:]
        var inlineCount = 0
        collectElementDecls(complexType, into: &byName, inlineCount: &inlineCount)
        return byName.keys.sorted().compactMap { name in
            (byName[name]?.count ?? 0) > 1
                ? "element '\(name)' has inconsistent type definitions in the same content model"
                : nil
        }
    }

    private static func collectElementDecls(_ node: XSDTree, into byName: inout [String: Set<String>], inlineCount: inout Int) {
        for child in PureXML.Schema.XSDNode.elementChildren(node) where child.name?.namespaceURI == xsdNamespace {
            guard let local = PureXML.Schema.XSDNode.localName(child) else { continue }
            if local == "element" {
                if let name = PureXML.Schema.XSDNode.attribute(child, "name") {
                    byName[name, default: []].insert(elementTypeKey(child, inlineCount: &inlineCount))
                }
                // Do not descend into the element's own type definition.
            } else if contentModelContainers.contains(local) {
                collectElementDecls(child, into: &byName, inlineCount: &inlineCount)
            }
        }
    }

    /// A key identifying an element particle's type definition: its `type`
    /// reference by local name, a distinct token per inline (anonymous) type (two
    /// inline types are never the same definition), or a shared token when the
    /// element is untyped (the ur-type).
    private static func elementTypeKey(_ element: XSDTree, inlineCount: inout Int) -> String {
        if let type = PureXML.Schema.XSDNode.attribute(element, "type") {
            return "type:" + PureXML.Schema.XSDNode.stripPrefix(type.trimmingXMLWhitespace())
        }
        let hasInlineType = PureXML.Schema.XSDNode.elementChildren(element).contains {
            let local = PureXML.Schema.XSDNode.localName($0)
            return local == "complexType" || local == "simpleType"
        }
        if hasInlineType {
            inlineCount += 1
            return "inline:\(inlineCount)"
        }
        return "untyped"
    }

    /// The model-group and content-derivation elements through which a complex
    /// type's content model extends; the walk descends through these but never
    /// into an element's own type definition (a nested type is a separate model).
    private static let contentModelContainers: Set<String> = [
        "sequence", "choice", "all", "group", "complexContent", "simpleContent", "restriction", "extension",
    ]
}
