extension PureXML.XSLT.Library {
    /// The XPath `id()` definition exactly: only attributes the DTD
    /// declares as type ID identify elements; a document without ID
    /// declarations yields the empty set.
    static func idLookup(
        _ arguments: [PureXML.XPath.Value],
        _ context: PureXML.XPath.EvaluationContext,
        _ documents: PureXML.XSLT.DocumentCache,
    ) -> PureXML.XPath.Value {
        let strings: [String] = if let nodes = arguments.first?.nodes {
            nodes.map(\.stringValue)
        } else {
            [arguments.first?.string ?? ""]
        }
        let tokens = Set(strings.flatMap { $0.split(whereSeparator: \.isWhitespace).map(String.init) })
        let owner: PureXML.Model.TreeNode? = switch context.node {
        case let .tree(tree): tree
        case let .attribute(treeOwner, _), let .namespace(treeOwner, _, _): treeOwner
        }
        guard !tokens.isEmpty, var documentRoot = owner else { return .nodeSet([]) }
        while let parent = documentRoot.parent {
            documentRoot = parent
        }
        guard let declared = documents.idAttributes[ObjectIdentifier(documentRoot)], !declared.isEmpty else {
            return .nodeSet([])
        }
        var matched: [PureXML.XPath.Node] = []
        collectIdentified(documentRoot, declared: declared, tokens: tokens, into: &matched)
        return .nodeSet(matched)
    }

    private static func collectIdentified(
        _ node: PureXML.Model.TreeNode,
        declared: [String: Set<String>],
        tokens: Set<String>,
        into matched: inout [PureXML.XPath.Node],
    ) {
        let idNames = node.name.flatMap { declared[$0.description] } ?? []
        let identified = node.kind == .element && !idNames.isEmpty
            && node.attributes.contains { idNames.contains($0.name.description) && tokens.contains($0.value) }
        if identified {
            matched.append(.tree(node))
        }
        for child in node.children {
            collectIdentified(child, declared: declared, tokens: tokens, into: &matched)
        }
    }

    /// The `key()` implementation: the index belongs to the current
    /// node's document; a node-set second argument unions the matches for
    /// each member's string value; results come back in document order.
    static func keyLookup(
        _ arguments: [PureXML.XPath.Value],
        _ context: PureXML.XPath.EvaluationContext,
        _ keys: (PureXML.Model.TreeNode) -> PureXML.XSLT.KeyIndex,
    ) -> PureXML.XPath.Value {
        let name = arguments.first?.string ?? ""
        guard arguments.count > 1 else { return .nodeSet([]) }
        let values: [String] = if let nodes = arguments[1].nodes {
            nodes.map(\.stringValue)
        } else {
            [arguments[1].string]
        }
        let owner: PureXML.Model.TreeNode? = switch context.node {
        case let .tree(tree): tree
        case let .attribute(treeOwner, _), let .namespace(treeOwner, _, _): treeOwner
        }
        guard var documentRoot = owner else { return .nodeSet([]) }
        while let parent = documentRoot.parent {
            documentRoot = parent
        }
        let index = keys(documentRoot)
        var matched: [PureXML.Model.TreeNode] = []
        for value in values {
            for node in index[name]?[value] ?? [] where !matched.contains(where: { $0 === node }) {
                matched.append(node)
            }
        }
        return .nodeSet(matched.map { PureXML.XPath.Node.tree($0) }.sorted(by: PureXML.XPath.Node.precedes))
    }
}
