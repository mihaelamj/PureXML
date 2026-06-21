private typealias ImportNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `src-import.3.1`/`3.2`: an `import`'s `namespace` attribute must equal
    /// the `targetNamespace` of the schema it resolves to (both present and equal, or
    /// both absent). Runs only past the cross-document skip guard, so the imported
    /// schema is loaded. Checked only when the `schemaLocation` resolved to a loaded
    /// container (an unresolved import is the processor's choice and not an error),
    /// which is the false-positive boundary. Imports keep their own target namespace
    /// (no chameleon), so the imported document's literal `targetNamespace` is used.
    static func importNamespaceFindings(_ context: PureXML.Schema.XSDContext, _ containers: [XSDTree]) -> [PureXML.Schema.SchemaLocatedFinding] {
        var locationTargetNS: [String: String?] = [:]
        for container in containers where ImportNode.localName(container) == "schema" {
            guard let location = context.containerLocations[ObjectIdentifier(container)] ?? nil else { continue }
            locationTargetNS[location] = ImportNode.attribute(container, "targetNamespace")
        }
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        for container in containers {
            for node in descendants(container, named: "import") where node.name?.namespaceURI == xsdNamespace {
                guard let location = ImportNode.attribute(node, "schemaLocation"),
                      locationTargetNS.keys.contains(location)
                else { continue }
                let imported = locationTargetNS[location] ?? nil
                let declared = ImportNode.attribute(node, "namespace")
                if declared != imported {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "import of '\(location)' declares namespace '\(declared ?? "(none)")', not the imported target namespace '\(imported ?? "(none)")'",
                        node: node,
                    ))
                }
            }
        }
        return findings
    }

    /// src-redefine.5: a type inside `xs:redefine` must restrict or extend the type it
    /// redefines, which lives in the redefining schema's OWN target namespace. So a
    /// base bound to an EXPLICIT different namespace (for example an imported type
    /// with the same local name) is not self and is invalid. A base with no resolvable
    /// namespace is left alone, which keeps this from ever over-rejecting a
    /// same-local-name self-reference.
    static func redefineBaseIsForeign(_ type: XSDTree, _ rawBase: String?) -> Bool {
        guard let rawBase else { return false }
        let schema = ImportNode.schemaOwner(type)
        let targetNamespace = ImportNode.attribute(schema, "targetNamespace")
        let bindings = ImportNode.namespaceBindings(of: schema)
        guard let baseNamespace = ImportNode.referenceNamespace(rawBase, bindings) else { return false }
        return baseNamespace != targetNamespace
    }
}
