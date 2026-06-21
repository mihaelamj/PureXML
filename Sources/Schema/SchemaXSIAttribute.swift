extension PureXML.Schema.XSDParser {
    private static let xsiInstanceNamespace = "http://www.w3.org/2001/XMLSchema-instance"

    /// XSD 1.0 Schema Component Constraint "xsi: Not Allowed" (§3.2.6): an attribute
    /// declaration's {target namespace} must not be the XSI namespace. A schema may
    /// target XSI and declare attributes there as long as they stay unqualified, so
    /// they land in no namespace (corpus attKb018, attKc018: valid). A top-level
    /// attribute, or a local one made qualified by `form="qualified"` or
    /// `attributeFormDefault="qualified"`, lands in the target namespace; when that is
    /// XSI it is forbidden (corpus attKb018a: `attributeFormDefault="qualified"` puts
    /// its attribute-group attributes into XSI). The check is scoped to schemas whose
    /// target namespace is XSI, the only documents that can place an attribute there.
    static func xsiNamespaceAttributeFindings(_ schema: XSDTree, _ context: PureXML.Schema.XSDContext) -> [PureXML.Schema.SchemaLocatedFinding] {
        guard context.targetNamespace == xsiInstanceNamespace else { return [] }
        let attributeFormDefault = PureXML.Schema.XSDNode.attribute(schema, "attributeFormDefault")
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        collectXSIAttributeFindings(schema, parentIsSchema: false, attributeFormDefault: attributeFormDefault, into: &findings)
        return findings
    }

    private static func collectXSIAttributeFindings(
        _ node: XSDTree,
        parentIsSchema: Bool,
        attributeFormDefault: String?,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        let isSchema = node.name?.namespaceURI == xsdNamespace && local == "schema"
        let isAttribute = node.name?.namespaceURI == xsdNamespace && local == "attribute"
        if isAttribute, PureXML.Schema.XSDNode.attribute(node, "ref") == nil, let name = PureXML.Schema.XSDNode.attribute(node, "name") {
            let form = PureXML.Schema.XSDNode.attribute(node, "form")
            let qualified = parentIsSchema || form == "qualified" || (form == nil && attributeFormDefault == "qualified")
            if qualified {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "attribute declaration '\(name)' is in the XSI namespace, which is not allowed (xsi: Not Allowed)",
                    node: node,
                ))
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectXSIAttributeFindings(child, parentIsSchema: isSchema, attributeFormDefault: attributeFormDefault, into: &findings)
        }
    }
}
