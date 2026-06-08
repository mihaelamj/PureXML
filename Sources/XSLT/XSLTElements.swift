extension PureXML.XSLT.Transformer {
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
