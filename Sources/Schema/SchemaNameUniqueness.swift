extension PureXML.Schema.XSDParser {
    /// Schema-validity findings for component-name uniqueness. Within a schema,
    /// global type names (simpleType and complexType share one symbol space),
    /// global element names, global attribute names, named model-group names, and
    /// named attribute-group names must each be unique; identity-constraint names
    /// (unique/key/keyref) must be unique across the whole schema. A duplicate was
    /// accepted, with a later definition silently overwriting the earlier one.
    ///
    /// Only the document's own globals are examined (`xs:redefine` children and
    /// included documents are not direct globals here), so a redefinition is not
    /// mistaken for a clash.
    static func componentNameErrors(_ schema: XSDTree) -> [String] {
        let globals = PureXML.Schema.XSDNode.elementChildren(schema)
            .filter { $0.name?.namespaceURI == xsdNamespace }
        var errors: [String] = []
        errors += duplicateNames(of: ["simpleType", "complexType"], in: globals, label: "type")
        errors += duplicateNames(of: ["element"], in: globals, label: "element")
        errors += duplicateNames(of: ["attribute"], in: globals, label: "attribute")
        errors += duplicateNames(of: ["group"], in: globals, label: "model group")
        errors += duplicateNames(of: ["attributeGroup"], in: globals, label: "attribute group")
        errors += identityConstraintNameErrors(schema)
        errors += keyrefReferErrors(schema)
        return errors
    }

    private struct KeyrefInfo {
        let name: String
        let refer: String
        let arity: Int
    }

    /// Findings for a `keyref` whose `refer` does not name a `key` or `unique` in
    /// the document, or whose field arity does not match the referenced key/unique's.
    /// Skipped when the document pulls in external definitions
    /// (`import`/`include`/`redefine`), which the default compile does not load,
    /// so a `refer` into them is never flagged.
    private static func keyrefReferErrors(_ schema: XSDTree) -> [String] {
        if hasExternalReference(schema) { return [] }
        var keyArities: [String: Int] = [:]
        var keyrefs: [KeyrefInfo] = []
        collectKeysAndRefers(schema, keyArities: &keyArities, keyrefs: &keyrefs)

        var errors: [String] = []
        for keyref in keyrefs {
            if let keyArity = keyArities[keyref.refer] {
                if keyArity != keyref.arity {
                    errors.append("keyref '\(keyref.name)' and its referenced key/unique '\(keyref.refer)' must have the same number of fields")
                }
            } else {
                errors.append("keyref refers to undeclared key or unique '\(keyref.refer)'")
            }
        }
        return errors
    }

    private static func collectKeysAndRefers(
        _ node: XSDTree,
        keyArities: inout [String: Int],
        keyrefs: inout [KeyrefInfo],
    ) {
        if let local = PureXML.Schema.XSDNode.localName(node), local == "appinfo" || local == "documentation" { return }
        if node.name?.namespaceURI == xsdNamespace, let local = PureXML.Schema.XSDNode.localName(node) {
            if local == "key" || local == "unique", let name = PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace() {
                let arity = PureXML.Schema.XSDNode.elementChildren(node)
                    .count(where: { $0.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName($0) == "field" })

                keyArities[name] = arity
            }
            if local == "keyref" {
                let name = PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace()
                let refer = PureXML.Schema.XSDNode.attribute(node, "refer")?.trimmingXMLWhitespace()
                if let name, let refer {
                    let arity = PureXML.Schema.XSDNode.elementChildren(node)
                        .count(where: { $0.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName($0) == "field" })
                    keyrefs.append(KeyrefInfo(name: name, refer: PureXML.Schema.XSDNode.stripPrefix(refer), arity: arity))
                }
            }
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectKeysAndRefers(child, keyArities: &keyArities, keyrefs: &keyrefs)
        }
    }

    /// Duplicate `name` values among the `kinds` components in `nodes`.
    private static func duplicateNames(of kinds: Set<String>, in nodes: [XSDTree], label: String) -> [String] {
        var seen: Set<String> = []
        var errors: [String] = []
        for node in nodes where kinds.contains(PureXML.Schema.XSDNode.localName(node) ?? "") {
            guard let name = PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace() else { continue }
            if !seen.insert(name).inserted {
                errors.append("duplicate \(label) name '\(name)'")
            }
        }
        return errors
    }

    /// Duplicate identity-constraint names anywhere in the schema document.
    private static func identityConstraintNameErrors(_ schema: XSDTree) -> [String] {
        var seen: Set<String> = []
        var errors: [String] = []
        func walk(_ node: XSDTree) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }
            if let name = identityConstraintName(node), !seen.insert(name).inserted {
                errors.append("duplicate identity constraint name '\(name)'")
            }
            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                walk(child)
            }
        }
        walk(schema)
        return errors
    }

    /// The `name` of `node` when it is an identity constraint (`unique`/`key`/
    /// `keyref`) in the XSD namespace, or nil.
    private static func identityConstraintName(_ node: XSDTree) -> String? {
        guard node.name?.namespaceURI == xsdNamespace,
              let local = PureXML.Schema.XSDNode.localName(node),
              ["unique", "key", "keyref"].contains(local)
        else { return nil }
        return PureXML.Schema.XSDNode.attribute(node, "name")?.trimmingXMLWhitespace()
    }
}
