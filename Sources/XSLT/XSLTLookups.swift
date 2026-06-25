extension PureXML.XSLT.Library {
    /// A QName-valued function argument (a key or decimal-format name) resolved
    /// to expanded form `{uri}local`, matching the expansion applied to the
    /// corresponding declaration's name. The prefix resolves against the
    /// expression's in-scope namespaces; an unprefixed or unbound name is left
    /// as is.
    static func expandedName(_ raw: String, _ namespaces: [String: String]) -> String {
        guard let colon = raw.firstIndex(of: ":"), let uri = namespaces[String(raw[..<colon])] else { return raw }
        return "{\(uri)}\(raw[raw.index(after: colon)...])"
    }

    /// The base URI against which a relative `document()` reference taken from
    /// this node resolves (XSLT 1.0 12.1): the URI the node's document was loaded
    /// from. The source document is absent from the map, so its base is the empty
    /// string, which leaves resolution to the loader's own base handling.
    static func baseURI(of node: PureXML.XPath.Node, _ documents: PureXML.XSLT.DocumentCache) -> String {
        let owner: PureXML.Model.TreeNode? = switch node {
        case let .tree(tree): tree
        case let .attribute(tree, _), let .namespace(tree, _, _): tree
        }
        guard var root = owner else { return "" }
        while let parent = root.parent {
            root = parent
        }
        return documents.baseURIs[ObjectIdentifier(root)] ?? ""
    }

    /// One `document()` reference resolved against its base URI; an empty base
    /// defers to the loader, which applies the source or stylesheet base itself.
    static func resolveDocumentReference(_ reference: String, against base: String) -> String {
        base.isEmpty ? reference : PureXML.XInclude.URIReference.resolve(reference, against: base)
    }

    /// The `xsl:key` match pattern as a path selecting every matching node: `//`
    /// is distributed over each top-level union branch (`a | b` becomes `//a |
    /// //b`, not `//a | b`), since the match is a pattern matched anywhere, not a
    /// single relative path.
    static func keyMatchPath(_ match: String) -> String {
        splitUnion(match).map { branch in
            let trimmed = branch.drop { $0 == " " }
            return trimmed.hasPrefix("/") ? String(trimmed) : "//" + trimmed
        }.joined(separator: " | ")
    }

    /// Splits a pattern on its top-level `|`, ignoring `|` inside a predicate
    /// `[...]` or a function call `(...)`.
    private static func splitUnion(_ pattern: String) -> [Substring] {
        var parts: [Substring] = []
        var depth = 0
        var start = pattern.startIndex
        var index = pattern.startIndex
        while index < pattern.endIndex {
            switch pattern[index] {
            case "[", "(": depth += 1
            case "]", ")": depth -= 1
            case "|" where depth == 0:
                parts.append(pattern[start ..< index])
                start = pattern.index(after: index)
            default: break
            }
            index = pattern.index(after: index)
        }
        parts.append(pattern[start...])
        return parts
    }

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
            .sortedByDocumentOrder()
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
        // The key name is matched by expanded QName (XSLT 1.0 12.2), matching
        // the expansion applied to the xsl:key declaration name.
        let name = expandedName(arguments.first?.string ?? "", context.namespaces)
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
        var seen: Set<ObjectIdentifier> = []
        for value in values {
            for node in index[name]?[value] ?? [] where seen.insert(ObjectIdentifier(node)).inserted {
                matched.append(node)
            }
        }
        return .nodeSet(matched.map { PureXML.XPath.Node.tree($0) }.sortedByDocumentOrder())
    }
}
