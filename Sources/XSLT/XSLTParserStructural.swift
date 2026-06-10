extension PureXML.XSLT.XSLTParser {
    static func structuralInstruction(_ node: XSLTTree) -> PureXML.XSLT.Instruction? {
        switch XSLTNode.localName(node) {
        case "for-each":
            .forEach(select: XSLTNode.attribute(node, "select") ?? "", sorts: sorts(node), body: body(node))
        case "if":
            .ifInstruction(test: XSLTNode.attribute(node, "test") ?? "", body: body(node))
        case "choose":
            choose(node)
        case "element":
            .element(
                name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""),
                namespace: XSLTNode.attribute(node, "namespace").map(valueTemplate),
                namespaces: inScopeNamespaces(node),
                useAttributeSets: useAttributeSets(node),
                body: body(node),
            )
        case "attribute":
            .attribute(
                name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""),
                namespace: XSLTNode.attribute(node, "namespace").map(valueTemplate),
                namespaces: inScopeNamespaces(node),
                body: body(node),
            )
        case "number":
            .number(PureXML.XSLT.NumberSpec(
                level: XSLTNode.attribute(node, "level") ?? "single",
                count: XSLTNode.attribute(node, "count"),
                from: XSLTNode.attribute(node, "from"),
                value: XSLTNode.attribute(node, "value"),
                format: XSLTNode.attribute(node, "format") ?? "1",
                groupingSeparator: XSLTNode.attribute(node, "grouping-separator"),
                groupingSize: XSLTNode.attribute(node, "grouping-size").flatMap { Int($0) },
            ))
        case "comment":
            .comment(body: body(node))
        case "processing-instruction":
            .processingInstruction(name: valueTemplate(XSLTNode.attribute(node, "name") ?? ""), body: body(node))
        default:
            nil
        }
    }

    /// The namespace bindings in scope at a stylesheet node, for resolving
    /// the prefix of a created name (7.1.2/7.1.3: the QName in a name
    /// attribute is expanded using the instruction's own declarations).
    static func inScopeNamespaces(_ node: XSLTTree) -> [String: String] {
        var bindings: [String: String] = [:]
        var current: XSLTTree? = node
        while let candidate = current {
            for attribute in candidate.attributes where attribute.name.prefix == "xmlns" {
                if bindings[attribute.name.localName] == nil {
                    bindings[attribute.name.localName] = attribute.value
                }
            }
            current = candidate.parent
        }
        return bindings
    }

    /// The namespace declarations a literal result element copies to the
    /// result (7.1.1): its in-scope bindings minus the XSLT namespace and
    /// the namespaces of the prefixes listed in `exclude-result-prefixes`
    /// and `extension-element-prefixes` in scope.
    static func copiedNamespaces(_ node: XSLTTree) -> [String: String] {
        var bindings = inScopeNamespaces(node)
        var current: XSLTTree? = node
        while let candidate = current {
            let defaults = candidate.attributes.filter { $0.name.prefix == nil && $0.name.localName == "xmlns" }
            if bindings[""] == nil, let declared = defaults.first { bindings[""] = declared.value }
            current = candidate.parent
        }
        var excludedURIs: Set<String> = [XSLTNode.namespace]
        for prefix in excludedPrefixTokens(node) {
            let key = prefix == "#default" ? "" : prefix
            if let uri = bindings[key] { excludedURIs.insert(uri) }
        }
        return bindings.filter { !excludedURIs.contains($0.value) && !($0.key.isEmpty && $0.value.isEmpty) }
    }

    /// Every `exclude-result-prefixes`/`extension-element-prefixes` token
    /// in scope at `node` (the unprefixed forms on xsl:stylesheet, the
    /// xsl-prefixed forms on literal elements).
    private static func excludedPrefixTokens(_ node: XSLTTree) -> [String] {
        var tokens: [String] = []
        var current: XSLTTree? = node
        while let candidate = current {
            for attribute in candidate.attributes {
                let local = attribute.name.localName
                guard local == "exclude-result-prefixes" || local == "extension-element-prefixes" else { continue }
                let isXSLElement = XSLTNode.isXSL(candidate)
                let qualified = attribute.name.prefix == "xsl"
                if isXSLElement == !qualified {
                    tokens += attribute.value.split(whereSeparator: \.isWhitespace).map(String.init)
                }
            }
            current = candidate.parent
        }
        return tokens
    }
}
