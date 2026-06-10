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
        let rootIdentity = ObjectIdentifier(documentRoot)
        guard let declared = documents.idAttributes[rootIdentity], !declared.isEmpty else {
            return .nodeSet([])
        }
        // The index is built once per document, not re-walked per call.
        let index: [String: PureXML.Model.TreeNode]
        if let cached = documents.idIndexes[rootIdentity] {
            index = cached
        } else {
            var built: [String: PureXML.Model.TreeNode] = [:]
            buildIDIndex(documentRoot, declared: declared, into: &built)
            documents.idIndexes[rootIdentity] = built
            index = built
        }
        let matched = index.filter { tokens.contains($0.key) }.values
            .map { PureXML.XPath.Node.tree($0) }
            .sorted(by: PureXML.XPath.Node.precedes)
        return .nodeSet(matched)
    }

    /// Walks the document once, indexing every DTD-identified element by
    /// its ID value; the first occurrence in document order wins.
    private static func buildIDIndex(
        _ node: PureXML.Model.TreeNode,
        declared: [String: Set<String>],
        into index: inout [String: PureXML.Model.TreeNode],
    ) {
        if node.kind == .element, let name = node.name?.description, let idNames = declared[name] {
            for attribute in node.attributes where idNames.contains(attribute.name.description) {
                if index[attribute.value] == nil { index[attribute.value] = node }
            }
        }
        for child in node.children {
            buildIDIndex(child, declared: declared, into: &index)
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
