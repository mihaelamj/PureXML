extension PureXML.Schema.XSDParser {
    /// The built-in type names a reference may name without a declaration: the
    /// XSD Part 2 datatypes, the built-in list types, and the ur-types.
    private static let referenceBuiltins: Set<String> = {
        var names = Set(PureXML.Schema.BuiltinType.allCases.map(\.rawValue))
        names.formUnion(["anyType", "anySimpleType", "anyAtomicType", "NOTATION", "IDREFS", "ENTITIES", "NMTOKENS"])
        return names
    }()

    /// Schema-validity findings for unresolvable references: every QName a schema
    /// names (a `type`/`base`/`itemType`/`memberTypes` type, an `element`/
    /// `attribute`/`group`/`attributeGroup` `ref`, an element `substitutionGroup`)
    /// must resolve to a declared component or a built-in. The reference is matched
    /// by local name, as the rest of the compiler resolves it.
    ///
    /// Skipped when the document pulls in external definitions through
    /// `import`/`include`/`redefine`: the default compile does not load them, so
    /// the pools would be incomplete and a reference into them must not be flagged.
    static func referenceErrors(_ schema: XSDTree, in context: PureXML.Schema.XSDContext, elements: [String: PureXML.Schema.ElementType]) -> [String] {
        if hasExternalReference(schema) { return [] }
        let types = referenceBuiltins.union(context.simpleTypes.keys).union(context.complexTypeNodes.keys)
        let pools: [String: Set<String>] = [
            "element": Set(elements.keys),
            "attribute": Set(context.globalAttributes.keys),
            "group": Set(context.groups.keys),
            "attributeGroup": Set(context.attributeGroups.keys),
        ]
        var errors: [String] = []
        collectReferenceErrors(schema, types: types, pools: pools, into: &errors)
        return errors
    }

    /// Whether the document declares an `import`, `include`, or `redefine`, so its
    /// component pools may be completed by an external document the default compile
    /// does not load.
    private static func hasExternalReference(_ schema: XSDTree) -> Bool {
        var found = false
        func walk(_ node: XSDTree) {
            if isExternalDefinition(node) {
                found = true
                return
            }
            for child in PureXML.Schema.XSDNode.elementChildren(node) where !found {
                walk(child)
            }
        }
        walk(schema)
        return found
    }

    /// Whether `node` is an `xs:import`/`xs:include`/`xs:redefine` (an XSD-namespace
    /// element bringing in external definitions).
    private static func isExternalDefinition(_ node: XSDTree) -> Bool {
        guard node.name?.namespaceURI == xsdNamespace, let local = PureXML.Schema.XSDNode.localName(node) else {
            return false
        }
        return local == "import" || local == "include" || local == "redefine"
    }

    private static func collectReferenceErrors(
        _ node: XSDTree,
        types: Set<String>,
        pools: [String: Set<String>],
        into errors: inout [String],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        if node.name?.namespaceURI == xsdNamespace, let local {
            errors += referenceErrors(at: node, local: local, types: types, pools: pools)
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectReferenceErrors(child, types: types, pools: pools, into: &errors)
        }
    }

    private static func referenceErrors(at node: XSDTree, local: String, types: Set<String>, pools: [String: Set<String>]) -> [String] {
        var errors: [String] = []
        for attribute in ["type", "base", "itemType"] {
            if let qname = PureXML.Schema.XSDNode.attribute(node, attribute), !types.contains(localName(qname)) {
                errors.append("\(attribute) references undeclared type '\(qname)'")
            }
        }
        if let members = PureXML.Schema.XSDNode.attribute(node, "memberTypes") {
            for token in members.split(whereSeparator: \.isWhitespace) where !types.contains(localName(String(token))) {
                errors.append("memberTypes references undeclared type '\(token)'")
            }
        }
        if let head = PureXML.Schema.XSDNode.attribute(node, "substitutionGroup"), pools["element"]?.contains(localName(head)) != true {
            errors.append("substitutionGroup references undeclared element '\(head)'")
        }
        if let reference = PureXML.Schema.XSDNode.attribute(node, "ref"), let pool = pools[local], !pool.contains(localName(reference)) {
            errors.append("\(local) ref references undeclared '\(reference)'")
        }
        return errors
    }

    /// The local part of a QName reference, after the whitespace normalization a
    /// `whiteSpace="collapse"` QName attribute receives (a value may be written
    /// with surrounding or, harmlessly, interior whitespace).
    private static func localName(_ qname: String) -> String {
        PureXML.Schema.XSDNode.stripPrefix(qname.trimmingXMLWhitespace())
    }
}
