extension PureXML.Schema.XSDParser {
    private struct ResolutionContext {
        let check: ReferenceCheckContext

        init(
            types: Set<String>,
            pools: [String: Set<String>],
            bindings: [String: String],
            targetNamespace: String?,
            foreignPools: [String?: [String: Set<String>]],
            chameleonNamespace: Bool,
        ) {
            check = ReferenceCheckContext(
                types: types,
                pools: pools,
                bindings: bindings,
                targetNamespace: targetNamespace,
                foreignPools: foreignPools,
                chameleonNamespace: chameleonNamespace,
            )
        }
    }

    /// Schema-validity findings for unresolvable references: every QName a schema
    /// names (a `type`/`base`/`itemType`/`memberTypes` type, an `element`/
    /// `attribute`/`group`/`attributeGroup` `ref`, an element `substitutionGroup`)
    /// must resolve to a declared component or a built-in. The reference is matched
    /// by local name, as the rest of the compiler resolves it.
    ///
    /// Skipped when the document pulls in external definitions through
    /// `import`/`include`/`redefine`: the default compile does not load them, so
    /// the pools would be incomplete and a reference into them must not be flagged.
    static func referenceErrors(
        _ schema: XSDTree,
        in context: PureXML.Schema.XSDContext,
        elements: [String: PureXML.Schema.ElementType],
        containers: [XSDTree],
    ) -> [String] {
        collectReferenceErrors(schema, in: context, elements: elements, containers: containers)
    }

    static func referenceFindings(
        _ schema: XSDTree,
        in context: PureXML.Schema.XSDContext,
        elements: [String: PureXML.Schema.ElementType],
        containers: [XSDTree],
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        PureXML.Schema.SchemaLocatedFinding.unlocated(
            collectReferenceErrors(schema, in: context, elements: elements, containers: containers),
        )
    }

    private static func collectReferenceErrors(
        _ schema: XSDTree,
        in context: PureXML.Schema.XSDContext,
        elements: [String: PureXML.Schema.ElementType],
        containers: [XSDTree],
    ) -> [String] {
        let xsdErrors = xsdNamespaceReferenceErrors(schema)
        let simpleContentErrors = simpleContentBaseErrors(schema, in: context)
        if skipsCrossDocumentRules(schema, compositionLoaded: context.compositionLoaded) {
            return xsdErrors + simpleContentErrors
        }
        let types = referenceBuiltins.union(context.simpleTypes.keys).union(context.complexTypeNodes.keys)
        let pools: [String: Set<String>] = [
            "element": Set(elements.keys),
            "attribute": Set(context.globalAttributes.keys),
            "group": Set(context.groups.keys),
            "attributeGroup": Set(context.attributeGroups.keys),
        ]
        let targetNamespace = context.targetNamespace
        let foreignPools = context.compositionLoaded
            ? foreignComponentPools(containers, mainTargetNamespace: targetNamespace)
            : [:]
        var errors: [String] = []
        let referenceSources: [(XSDTree, String?)]
        if context.compositionLoaded {
            let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: targetNamespace)
            referenceSources = containers.compactMap { container -> (XSDTree, String?)? in
                guard PureXML.Schema.XSDNode.localName(container) == "schema" else { return nil }
                let index = containers.firstIndex(where: { $0 === container }) ?? containers.count - 1
                let effectiveNamespace = namespaceMap[index] ?? targetNamespace
                return (container, effectiveNamespace)
            }
        } else {
            referenceSources = [(schema, targetNamespace)]
        }
        for (source, effectiveNamespace) in referenceSources {
            let sourceBindings = PureXML.Schema.XSDNode.namespaceBindings(of: source)
            let chameleonNamespace = PureXML.Schema.XSDNode.attribute(source, "targetNamespace") == nil
            let resolutionContext = ResolutionContext(
                types: types,
                pools: pools,
                bindings: sourceBindings,
                targetNamespace: effectiveNamespace,
                foreignPools: foreignPools,
                chameleonNamespace: chameleonNamespace,
            )
            collectReferenceErrors(source, in: resolutionContext, inheritedBindings: sourceBindings, into: &errors)
        }
        return xsdErrors + simpleContentErrors + errors
    }

    /// Whether cross-document schema-validity rules should stand down: an external
    /// reference is declared but no external document was loaded through a
    /// `schemaLoader`, so the merged component set is incomplete.
    static func skipsCrossDocumentRules(_ schema: XSDTree, compositionLoaded: Bool) -> Bool {
        hasExternalReference(schema) && !compositionLoaded
    }

    /// Whether the document declares an `import`, `include`, or `redefine`, so its
    /// component pools may be completed by an external document the default compile
    /// does not load.
    static func hasExternalReference(_ schema: XSDTree) -> Bool {
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
        in resolutionContext: ResolutionContext,
        inheritedBindings: [String: String],
        into errors: inout [String],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }
        let bindings = mergedNamespaceBindings(on: node, inherited: inheritedBindings)
        let nodeContext = ResolutionContext(
            types: resolutionContext.check.types,
            pools: resolutionContext.check.pools,
            bindings: bindings,
            targetNamespace: resolutionContext.check.targetNamespace,
            foreignPools: resolutionContext.check.foreignPools,
            chameleonNamespace: resolutionContext.check.chameleonNamespace,
        )
        if node.name?.namespaceURI == xsdNamespace, let local {
            errors += referenceErrors(at: node, local: local, in: nodeContext)
        }
        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            collectReferenceErrors(child, in: resolutionContext, inheritedBindings: bindings, into: &errors)
        }
    }

    private static func referenceErrors(
        at node: XSDTree,
        local: String,
        in resolutionContext: ResolutionContext,
    ) -> [String] {
        var errors: [String] = []
        let context = resolutionContext.check
        for attribute in ["type", "base", "itemType"] {
            guard let qname = PureXML.Schema.XSDNode.attribute(node, attribute) else { continue }
            if isUndeclaredReferenceType(qname, in: context) {
                errors.append("\(attribute) references undeclared type '\(qname)'")
            }
        }
        if let members = PureXML.Schema.XSDNode.attribute(node, "memberTypes") {
            for token in members.split(whereSeparator: \.isWhitespace) {
                let qname = String(token)
                if isUndeclaredReferenceType(qname, in: context) {
                    errors.append("memberTypes references undeclared type '\(qname)'")
                }
            }
        }
        if let head = PureXML.Schema.XSDNode.attribute(node, "substitutionGroup") {
            if isUndeclaredReferenceRef(head, poolName: "element", in: context) {
                errors.append("substitutionGroup references undeclared element '\(head)'")
            }
        }
        if let reference = PureXML.Schema.XSDNode.attribute(node, "ref"), context.pools[local] != nil {
            if isUndeclaredReferenceRef(reference, poolName: local, in: context) {
                errors.append("\(local) ref references undeclared '\(reference)'")
            }
        }
        return errors
    }

    static func simpleTypeBaseNotComplexErrors(_ schema: XSDTree, in context: PureXML.Schema.XSDContext) -> [String] {
        var errors: [String] = []
        let bindings = PureXML.Schema.XSDNode.namespaceBindings(of: schema)
        let targetNamespace = context.targetNamespace

        func isComplex(_ qname: String) -> Bool {
            let trimmed = qname.trimmingXMLWhitespace()
            let prefix = PureXML.Schema.XSDNode.prefix(trimmed)
            let uri = prefix.flatMap { bindings[$0] } ?? bindings[""]
            let local = PureXML.Schema.XSDNode.stripPrefix(trimmed)
            if uri == xsdNamespace {
                if targetNamespace == xsdNamespace {
                    return local == "anyType" || context.complexTypeNodes[local] != nil
                } else {
                    return local == "anyType"
                }
            }
            if uri == targetNamespace || uri == nil || uri == "" {
                return context.complexTypeNodes[local] != nil
            }
            return false
        }

        func check(_ node: XSDTree) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }

            if node.name?.namespaceURI == xsdNamespace {
                switch local {
                case "restriction":
                    Self.checkRestrictionUnderSimpleType(node, isComplex: isComplex, errors: &errors)
                case "list":
                    Self.checkList(node, isComplex: isComplex, errors: &errors)
                case "union":
                    Self.checkUnion(node, isComplex: isComplex, errors: &errors)
                default:
                    break
                }
            }

            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                check(child)
            }
        }
        check(schema)
        return errors
    }

    private static func checkRestrictionUnderSimpleType(_ node: XSDTree, isComplex: (String) -> Bool, errors: inout [String]) {
        guard let parent = node.parent, parent.name?.namespaceURI == xsdNamespace, PureXML.Schema.XSDNode.localName(parent) == "simpleType" else { return }
        if let base = PureXML.Schema.XSDNode.attribute(node, "base"), isComplex(base) {
            errors.append("base type '\(base)' of simpleType restriction must be a simple type, not a complex type")
        }
    }

    private static func checkList(_ node: XSDTree, isComplex: (String) -> Bool, errors: inout [String]) {
        if let itemType = PureXML.Schema.XSDNode.attribute(node, "itemType"), isComplex(itemType) {
            errors.append("itemType '\(itemType)' of list must be a simple type, not a complex type")
        }
    }

    private static func checkUnion(_ node: XSDTree, isComplex: (String) -> Bool, errors: inout [String]) {
        if let members = PureXML.Schema.XSDNode.attribute(node, "memberTypes") {
            for token in members.split(whereSeparator: \.isWhitespace) where isComplex(String(token)) {
                errors.append("memberType '\(token)' of union must be a simple type, not a complex type")
            }
        }
    }

    private static func xsdNamespaceReferenceErrors(_ schema: XSDTree) -> [String] {
        let targetNamespace = PureXML.Schema.XSDNode.attribute(schema, "targetNamespace")
        if targetNamespace == xsdNamespace {
            return []
        }
        var errors: [String] = []
        let bindings = PureXML.Schema.XSDNode.namespaceBindings(of: schema)

        func isUndeclaredBuiltin(_ qname: String) -> Bool {
            let prefix = PureXML.Schema.XSDNode.prefix(qname)
            let uri = prefix.flatMap { bindings[$0] } ?? bindings[""]
            if uri == xsdNamespace {
                let localName = PureXML.Schema.XSDNode.stripPrefix(qname)
                return !referenceBuiltins.contains(localName)
            }
            return false
        }

        func check(_ node: XSDTree) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }

            if node.name?.namespaceURI == xsdNamespace {
                for attribute in ["type", "base", "itemType"] {
                    if let qname = PureXML.Schema.XSDNode.attribute(node, attribute), isUndeclaredBuiltin(qname) {
                        errors.append("\(attribute) references undeclared type '\(qname)'")
                    }
                }
                if let members = PureXML.Schema.XSDNode.attribute(node, "memberTypes") {
                    for token in members.split(whereSeparator: \.isWhitespace) {
                        let qname = String(token)
                        if isUndeclaredBuiltin(qname) {
                            errors.append("memberTypes references undeclared type '\(qname)'")
                        }
                    }
                }
            }

            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                check(child)
            }
        }
        check(schema)
        return errors
    }

    private static func simpleContentBaseErrors(_ schema: XSDTree, in context: PureXML.Schema.XSDContext) -> [String] {
        var errors: [String] = []
        let bindings = PureXML.Schema.XSDNode.namespaceBindings(of: schema)
        let targetNamespace = context.targetNamespace

        func check(_ node: XSDTree) {
            let local = PureXML.Schema.XSDNode.localName(node)
            if local == "appinfo" || local == "documentation" { return }

            let isSimpleContentRestriction = node.name?.namespaceURI == xsdNamespace && local == "restriction"
                && node.parent?.name?.namespaceURI == xsdNamespace
                && node.parent.flatMap { PureXML.Schema.XSDNode.localName($0) } == "simpleContent"
            if isSimpleContentRestriction {
                if let base = PureXML.Schema.XSDNode.attribute(node, "base") {
                    let prefix = PureXML.Schema.XSDNode.prefix(base)
                    let uri = prefix.flatMap { bindings[$0] } ?? bindings[""]
                    let localPart = PureXML.Schema.XSDNode.stripPrefix(base)
                    if uri == targetNamespace || uri == nil || uri == "" {
                        if let baseNode = context.complexTypeNodes[localPart] {
                            let children = PureXML.Schema.XSDNode.elementChildren(baseNode)
                            let hasSimpleContent = children.contains { child in
                                child.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName(child) == "simpleContent"
                            }
                            if !hasSimpleContent {
                                errors.append("base type '\(base)' of simpleContent restriction must be a simple type or complex type with simpleContent")
                            }
                        }
                    }
                }
            }

            for child in PureXML.Schema.XSDNode.elementChildren(node) {
                check(child)
            }
        }
        check(schema)
        return errors
    }
}
