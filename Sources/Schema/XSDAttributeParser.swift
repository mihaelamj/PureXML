extension PureXML.Schema.XSDParser {
    /// The attribute uses declared directly under `node` and through any
    /// `attributeGroup` references it nests, flattened. The `visited` set guards
    /// against attribute-group reference cycles.
    static func attributeUses(under node: XSDTree, _ context: PureXML.Schema.XSDContext, visited: Set<String> = []) -> [PureXML.Schema.AttributeUse] {
        var uses: [PureXML.Schema.AttributeUse] = []
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            switch PureXML.Schema.XSDNode.localName(child) {
            case "attribute":
                if let use = attributeUse(child, context) { uses.append(use) }
            case "attributeGroup":
                guard let ref = PureXML.Schema.XSDNode.attribute(child, "ref") else { break }
                let name = PureXML.Schema.XSDNode.stripPrefix(ref)
                guard !visited.contains(name), let group = context.attributeGroups[name] else { break }
                uses += attributeUses(under: group, context, visited: visited.union([name]))
            default:
                break
            }
        }
        return uses
    }

    /// Prefix bindings in effect on `node`: the enclosing schema's `xmlns` declarations
    /// merged along the ancestor path (used for `ref` QNames inside included documents).
    static func namespaceBindingsInScope(of node: XSDTree, defaultBindings: [String: String]) -> [String: String] {
        var path: [XSDTree] = []
        var current: XSDTree? = node
        while let currentNode = current {
            path.append(currentNode)
            current = currentNode.parent
        }
        path.reverse()
        let schemaRoot = path.first { PureXML.Schema.XSDNode.localName($0) == "schema" }
        var bindings = schemaRoot.map { PureXML.Schema.XSDNode.namespaceBindings(of: $0) } ?? defaultBindings
        for ancestor in path {
            bindings = mergedNamespaceBindings(on: ancestor, inherited: bindings)
        }
        return bindings
    }

    static func attributeUse(_ node: XSDTree, _ context: PureXML.Schema.XSDContext) -> PureXML.Schema.AttributeUse? {
        // An `<attribute ref="...">` references a global attribute declaration:
        // take its name (always target-namespace qualified) and type from the
        // global node, but `use`/`default`/`fixed` from this reference site.
        if let ref = PureXML.Schema.XSDNode.attribute(node, "ref") {
            let refName = PureXML.Schema.XSDNode.stripPrefix(ref)
            guard let declaration = context.globalAttributes[refName],
                  var use = attributeUse(declaration, context) else { return nil }
            let bindings = namespaceBindingsInScope(of: node, defaultBindings: context.namespaceBindings)
            let namespace = PureXML.Schema.XSDNode.referenceNamespace(ref, bindings)
            use.name = PureXML.Model.QualifiedName(localName: refName, namespaceURI: namespace)
            if PureXML.Schema.XSDNode.attribute(node, "use") == "required" { use.required = true }
            if let constraint = valueConstraint(of: node) { use.valueConstraint = constraint }
            return use
        }
        guard let name = PureXML.Schema.XSDNode.attribute(node, "name") else { return nil }
        let required = PureXML.Schema.XSDNode.attribute(node, "use") == "required"
        let type: PureXML.Schema.SimpleType = if let typeName = PureXML.Schema.XSDNode.attribute(node, "type") {
            PureXML.Schema.XSDSimpleParser.simpleTypeReference(typeName, context)
        } else if let inline = PureXML.Schema.XSDNode.firstChild(node, named: "simpleType") {
            PureXML.Schema.XSDSimpleParser.simpleType(inline, context)
        } else {
            PureXML.Schema.SimpleType(base: .string, isAnySimpleType: true)
        }
        let qualified = PureXML.Schema.XSDNode.attribute(node, "form") == "qualified"
            || (PureXML.Schema.XSDNode.attribute(node, "form") == nil && context.attributeFormQualified)
        return PureXML.Schema.AttributeUse(
            name: PureXML.Model.QualifiedName(localName: name, namespaceURI: qualified ? context.targetNamespace : nil),
            type: type,
            required: required,
            valueConstraint: valueConstraint(of: node),
        )
    }
}
