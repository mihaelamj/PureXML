extension PureXML.Schema.XSDParser {
    static func notationValidityFindings(
        _ containers: [XSDTree],
        _ context: PureXML.Schema.XSDContext,
    ) -> [PureXML.Schema.SchemaLocatedFinding] {
        let namespaceMap = resolveContainerNamespaces(containers, mainTargetNamespace: context.targetNamespace)
        var findings: [PureXML.Schema.SchemaLocatedFinding] = []
        var declaredNotations: Set<PureXML.Model.QualifiedName> = []

        // 1. Collect all declared notations and validate notation declarations
        for index in containers.indices {
            let container = containers[index]
            let containerNamespace = namespaceMap[index] ?? context.targetNamespace
            for child in PureXML.Schema.XSDNode.elementChildren(container) {
                guard child.name?.namespaceURI == xsdNamespace,
                      PureXML.Schema.XSDNode.localName(child) == "notation"
                else {
                    continue
                }
                let name = PureXML.Schema.XSDNode.attribute(child, "name") ?? ""
                if PureXML.Schema.XSDNode.attribute(child, "public") == nil, PureXML.Schema.XSDNode.attribute(child, "system") == nil {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "notation '\(name)' must specify at least one of public or system attributes",
                        node: child,
                    ))
                }
                if notationHasForbiddenContent(child) {
                    findings.append(PureXML.Schema.SchemaLocatedFinding(
                        reason: "notation '\(name)' may contain only an optional annotation, no other element or character content",
                        node: child,
                    ))
                }
                let qName = PureXML.Model.QualifiedName(localName: name, namespaceURI: containerNamespace)
                declaredNotations.insert(qName)
            }
        }

        // 2. Validate notation enumeration constraints on simpleTypes
        for index in containers.indices {
            let container = containers[index]
            walkSimpleTypes(container, context: context, declaredNotations: declaredNotations, into: &findings)
        }

        return findings
    }

    /// Whether a `notation` declaration carries content its `(annotation?)` model
    /// forbids: any element child other than an `xsd:annotation`, or any
    /// non-whitespace character content. Whitespace and a single optional
    /// annotation are allowed.
    private static func notationHasForbiddenContent(_ node: XSDTree) -> Bool {
        let hasForeignElement = PureXML.Schema.XSDNode.elementChildren(node).contains {
            $0.name?.namespaceURI != xsdNamespace || PureXML.Schema.XSDNode.localName($0) != "annotation"
        }
        let hasText = node.children.contains {
            ($0.kind == .text || $0.kind == .cdata) && $0.value.contains { !$0.isWhitespace }
        }
        return hasForeignElement || hasText
    }

    private static func walkSimpleTypes(
        _ node: XSDTree,
        context: PureXML.Schema.XSDContext,
        declaredNotations: Set<PureXML.Model.QualifiedName>,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        let local = PureXML.Schema.XSDNode.localName(node)
        if local == "appinfo" || local == "documentation" { return }

        if node.name?.namespaceURI == xsdNamespace, local == "restriction" {
            validateNotationRestriction(node, context: context, declaredNotations: declaredNotations, into: &findings)
        }

        for child in PureXML.Schema.XSDNode.elementChildren(node) {
            walkSimpleTypes(child, context: context, declaredNotations: declaredNotations, into: &findings)
        }
    }

    private static func validateNotationRestriction(
        _ node: XSDTree,
        context: PureXML.Schema.XSDContext,
        declaredNotations: Set<PureXML.Model.QualifiedName>,
        into findings: inout [PureXML.Schema.SchemaLocatedFinding],
    ) {
        guard let parent = node.parent,
              parent.name?.namespaceURI == xsdNamespace,
              PureXML.Schema.XSDNode.localName(parent) == "simpleType",
              let baseAttr = PureXML.Schema.XSDNode.attribute(node, "base")
        else {
            return
        }
        let baseType = PureXML.Schema.XSDSimpleParser.simpleTypeReference(baseAttr, context)
        guard baseType.base == PureXML.Schema.BuiltinType.notation else { return }

        let bindings = collectBindings(from: node)
        for child in PureXML.Schema.XSDNode.elementChildren(node) where child.name?.namespaceURI == xsdNamespace && PureXML.Schema.XSDNode.localName(child) == "enumeration" {
            guard let value = PureXML.Schema.XSDNode.attribute(child, "value") else { continue }
            let prefix = PureXML.Schema.XSDNode.prefix(value)
            let resolvedNamespace = prefix == "xml" ? "http://www.w3.org/XML/1998/namespace" : PureXML.Schema.XSDNode.referenceNamespace(value, bindings)
            let localVal = PureXML.Schema.XSDNode.stripPrefix(value)
            let valQName = PureXML.Model.QualifiedName(prefix: prefix, localName: localVal, namespaceURI: resolvedNamespace)
            let isDeclared = declaredNotations.contains { dec in
                let decNS = (dec.namespaceURI == "") ? nil : dec.namespaceURI
                let valNS = (valQName.namespaceURI == "") ? nil : valQName.namespaceURI
                return dec.localName == valQName.localName && decNS == valNS
            }
            if !isDeclared {
                findings.append(PureXML.Schema.SchemaLocatedFinding(
                    reason: "notation enumeration value '\(value)' does not name a declared notation",
                    node: child,
                ))
            }
        }
    }

    private static func collectBindings(from node: XSDTree) -> [String: String] {
        var bindings: [String: String] = [:]
        var current: XSDTree? = node
        while let element = current {
            for (prefix, uri) in PureXML.Schema.XSDNode.namespaceBindings(of: element) where bindings[prefix] == nil {
                bindings[prefix] = uri
            }
            current = element.parent
        }
        return bindings
    }
}
