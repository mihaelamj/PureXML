extension PureXML.XSLT.Transformer {
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
