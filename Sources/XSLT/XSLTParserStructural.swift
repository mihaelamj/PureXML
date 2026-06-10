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
            .number(
                count: XSLTNode.attribute(node, "count"),
                from: XSLTNode.attribute(node, "from"),
                format: XSLTNode.attribute(node, "format") ?? "1",
            )
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
}
