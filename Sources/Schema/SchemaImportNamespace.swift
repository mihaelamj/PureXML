private typealias ImportNode = PureXML.Schema.XSDNode

extension PureXML.Schema.XSDParser {
    /// XSD 1.0 `src-import.3.1`/`3.2`: an `import`'s `namespace` attribute must equal
    /// the `targetNamespace` of the schema it resolves to (both present and equal, or
    /// both absent). Runs only past the cross-document skip guard, so the imported
    /// schema is loaded. Checked only when the `schemaLocation` resolved to a loaded
    /// container (an unresolved import is the processor's choice and not an error),
    /// which is the false-positive boundary. Imports keep their own target namespace
    /// (no chameleon), so the imported document's literal `targetNamespace` is used.
    static func importNamespaceErrors(_ context: PureXML.Schema.XSDContext, _ containers: [XSDTree]) -> [String] {
        var locationTargetNS: [String: String?] = [:]
        for container in containers where ImportNode.localName(container) == "schema" {
            guard let location = context.containerLocations[ObjectIdentifier(container)] ?? nil else { continue }
            locationTargetNS[location] = ImportNode.attribute(container, "targetNamespace")
        }
        var errors: [String] = []
        for container in containers {
            for node in descendants(container, named: "import") where node.name?.namespaceURI == xsdNamespace {
                guard let location = ImportNode.attribute(node, "schemaLocation"),
                      locationTargetNS.keys.contains(location)
                else { continue }
                let imported = locationTargetNS[location] ?? nil
                let declared = ImportNode.attribute(node, "namespace")
                if declared != imported {
                    errors.append("import of '\(location)' declares namespace '\(declared ?? "(none)")', not the imported target namespace '\(imported ?? "(none)")'")
                }
            }
        }
        return errors
    }
}
