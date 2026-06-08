extension PureXML.XSLT.Transformer {
    /// The attributes contributed by `names` and the attribute sets they include,
    /// lower precedence first, with a `visiting` guard against recursive includes.
    func attributeSetAttributes(_ names: [String], _ context: XSLTContext, visiting: Set<String>) -> [PureXML.Model.Attribute] {
        var result: [PureXML.Model.Attribute] = []
        for name in names where !visiting.contains(name) {
            guard let set = stylesheet.attributeSets[name] else { continue }
            result += attributeSetAttributes(set.use, context, visiting: visiting.union([name]))
            for item in instantiate(set.attributes, context) {
                if case let .attribute(attribute) = item { result.append(attribute) }
            }
        }
        return result
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
