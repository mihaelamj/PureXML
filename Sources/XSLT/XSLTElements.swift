extension PureXML.XSLT.Transformer {
    /// Compares strings case-insensitively, with `caseOrder` breaking ties among
    /// strings that differ only in case (the XSLT `case-order` semantics).
    static func caseInsensitiveCompare(_ left: String, _ right: String, _ caseOrder: PureXML.XSLT.CaseOrder) -> Int {
        let leftLower = left.lowercased()
        let rightLower = right.lowercased()
        if leftLower != rightLower { return leftLower < rightLower ? -1 : 1 }
        if left == right { return 0 }
        // Equal apart from case: codepoint order puts uppercase first.
        let upperFirst = left < right
        let leftFirst = caseOrder == .upperFirst ? upperFirst : !upperFirst
        return leftFirst ? -1 : 1
    }

    /// Rewrites a literal name in an `xsl:namespace-alias`ed stylesheet namespace
    /// to its result namespace and prefix; other names pass through unchanged.
    func aliased(_ name: PureXML.Model.QualifiedName) -> PureXML.Model.QualifiedName {
        guard let alias = stylesheet.namespaceAliases[name.namespaceURI ?? ""] else { return name }
        return PureXML.Model.QualifiedName(prefix: alias.prefix, localName: name.localName, namespaceURI: alias.uri)
    }

    /// The attributes with duplicates by name removed, keeping the last (so a
    /// later attribute overrides one from an attribute set or an earlier source).
    static func deduplicated(_ attributes: [PureXML.Model.Attribute]) -> [PureXML.Model.Attribute] {
        var indexByName: [String: Int] = [:]
        var result: [PureXML.Model.Attribute] = []
        for attribute in attributes {
            if let index = indexByName[attribute.name.description] {
                result[index] = attribute
            } else {
                indexByName[attribute.name.description] = result.count
                result.append(attribute)
            }
        }
        return result
    }
}
