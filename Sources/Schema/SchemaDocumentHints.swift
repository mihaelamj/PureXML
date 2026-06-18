extension PureXML.Schema.Document {
    /// The schema-document locations an instance points at through
    /// `xsi:schemaLocation` (the second token of each namespace/location pair)
    /// and `xsi:noNamespaceSchemaLocation` (a single location).
    static func hintedSchemaLocations(in node: PureXML.Model.Node) -> [String] {
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            return []
        }
        var locations: [String] = []
        for attribute in root.attributes {
            let isInstance = attribute.name.namespaceURI == "http://www.w3.org/2001/XMLSchema-instance"
                || attribute.name.prefix == "xsi"
            guard isInstance else { continue }
            switch attribute.name.localName {
            case "schemaLocation":
                let tokens = attribute.value.split(whereSeparator: \.isWhitespace).map(String.init)
                var index = 1
                while index < tokens.count {
                    locations.append(tokens[index])
                    index += 2
                }
            case "noNamespaceSchemaLocation":
                locations.append(attribute.value)
            default:
                break
            }
        }
        return locations
    }
}
