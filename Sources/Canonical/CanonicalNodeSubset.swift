extension PureXML.Canonical.Canonicalizer {
    /// The apex element with its inherited `xml:*` attributes added, and (for
    /// inclusive mode) the namespaces in scope from omitted ancestors merged in
    /// as declarations so the apex renders its full namespace context.
    static func augmentedApex(
        _ apex: PureXML.Model.Element,
        inheritedXML: [PureXML.Model.Attribute],
        mergingNamespaces ancestorNamespaces: [String: String]?,
        stripApexBase: Bool,
    ) -> PureXML.Model.Element {
        // Under 1.1, the apex's own xml:base is folded into the merged base in
        // inheritedXML, so drop the original to avoid emitting it twice.
        let own = stripApexBase
            ? apex.attributes.filter { !($0.name.prefix == "xml" && $0.name.localName == "base") }
            : apex.attributes
        var attributes = own + inheritedXML
        if let ancestorNamespaces {
            let declared = Set(apex.attributes.map(\.name.description))
            for (prefix, uri) in ancestorNamespaces {
                let name = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)"
                if !declared.contains(name) { attributes.append(PureXML.Model.Attribute(name, uri)) }
            }
        }
        return PureXML.Model.Element(name: apex.name, attributes: attributes, children: apex.children)
    }

    /// The namespace declarations in scope from a node's omitted ancestors,
    /// nearest ancestor winning (so an inner redeclaration is preserved).
    static func inScopeNamespaces(above node: PureXML.Model.TreeNode) -> [String: String] {
        var result: [String: String] = [:]
        var current = node.parent
        while let ancestor = current {
            for attribute in ancestor.attributes {
                guard let prefix = declaredPrefix(of: attribute.name), result[prefix] == nil else { continue }
                result[prefix] = attribute.value
            }
            current = ancestor.parent
        }
        return result
    }

    /// The `xml:*` attributes in scope from a node's omitted ancestors that the
    /// apex does not already set, nearest ancestor winning.
    static func inheritedXMLAttributes(above node: PureXML.Model.TreeNode, apex: PureXML.Model.Element, mergeBase: Bool) -> [PureXML.Model.Attribute] {
        let present = Set(apex.attributes.map(\.name.description))
        if mergeBase { return inherited11XMLAttributes(above: node, apex: apex, present: present) }
        // Canonical XML 1.0: the nearest of every in-scope xml:* attribute the
        // apex does not already set.
        var seen: Set<String> = []
        var result: [PureXML.Model.Attribute] = []
        var current = node.parent
        while let ancestor = current {
            for attribute in ancestor.attributes where attribute.name.prefix == "xml" {
                let key = attribute.name.description
                guard !present.contains(key), seen.insert(key).inserted else { continue }
                result.append(attribute)
            }
            current = ancestor.parent
        }
        return result
    }

    /// The prefix a namespace declaration binds (empty for the default
    /// namespace), or nil when the attribute is not a namespace declaration.
    static func declaredPrefix(of name: PureXML.Model.QualifiedName) -> String? {
        if name.prefix == nil, name.localName == "xmlns" { return "" }
        if name.prefix == "xmlns" { return name.localName }
        return nil
    }
}
