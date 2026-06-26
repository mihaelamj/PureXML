extension PureXML.Schema.XSDParser {
    /// Schema-validity findings for the `id` attributes in a schema document. The
    /// `id` attribute on any XSD component is of type `xs:ID`, so each value must
    /// be a valid NCName and all values must be unique within the document
    /// (XSD Structures: `xs:ID` and the ID/IDREF constraints). The values were
    /// never checked, so a malformed (`id=""`, `id="123"`) or duplicated `id` left
    /// the schema wrongly accepted.
    ///
    /// Walks the one document rooted at `schema`; an included or imported document
    /// keeps its own `id` scope, so cross-document collisions are not flagged here.
    static func idAttributeFindings(_ schema: XSDTree) -> [PureXML.Schema.SchemaLocatedFinding] {
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        var seen: Set<String> = []
        collectIDFindings(schema, into: &findings, seen: &seen)
        return findings
    }

    private static func collectIDFindings(
        _ node: XSDTree,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
        seen: inout Set<String>,
    ) {
        // `appinfo` and `documentation` hold arbitrary foreign content whose own
        // `id` attributes are not xs:ID; do not descend into them.
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if let id = unprefixedID(node) {
            if !PureXML.Schema.Lexical.isNCName(id) {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "id attribute value '\(id)' is not a valid NCName",
                    node: node,
                ))
            } else if !seen.insert(id).inserted {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "duplicate id attribute value '\(id)' in the schema document",
                    node: node,
                ))
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectIDFindings(child, into: &findings, seen: &seen)
        }
    }

    /// The value of the unprefixed, no-namespace `id` attribute (the xs:ID one),
    /// or nil. A prefixed attribute such as `xml:id` or a foreign `pre:id` is a
    /// different attribute and is not the schema-component identifier.
    private static func unprefixedID(_ node: XSDTree) -> String? {
        node.attributes.first { $0.name.prefix == nil && $0.name.localName == "id" }?.value
    }
}
