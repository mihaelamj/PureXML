/// A node queued for sorting: its original offset and computed keys.
private struct SortEntry {
    let offset: Int
    let node: PureXML.XPath.Node
    let keys: [String]
}

extension PureXML.XSLT.Transformer {
    func sorted(_ nodes: [PureXML.XPath.Node], _ sorts: [PureXML.XSLT.Sort], _ context: XSLTContext) -> [PureXML.XPath.Node] {
        guard !sorts.isEmpty else { return nodes }
        // Keys are computed once per node with the node's own evaluation
        // context (its position and size in the selection, the caller's
        // variables and bindings), so position()-based keys work.
        let keyed = nodes.enumerated().map { offset, xnode -> SortEntry in
            guard let owner = Self.ownerNode(xnode) else { return SortEntry(offset: offset, node: xnode, keys: sorts.map { _ in "" }) }
            var keyContext = XSLTContext(
                node: owner,
                current: xnode.treeNode == nil ? xnode : nil,
                position: offset + 1,
                size: nodes.count,
                variables: context.variables,
            )
            keyContext.namespaces = context.namespaces
            keyContext.baseURI = context.baseURI
            return SortEntry(offset: offset, node: xnode, keys: sorts.map { string($0.select, keyContext) })
        }
        // A lang attribute value template evaluates once per sort, in the
        // caller's context; a known language selects its tailored alphabet.
        let tailorings: [[Character: Int]?] = sorts.map { sort in
            sort.lang.flatMap { PureXML.XSLT.Collation.table(for: avt($0, context)) }
        }
        return keyed.sorted { lhs, rhs in
            for (index, sort) in sorts.enumerated() {
                let order: Int
                if !sort.numeric, sort.caseOrder == nil, let ranks = tailorings[index] {
                    let tailored = PureXML.XSLT.Collation.compare(lhs.keys[index], rhs.keys[index], ranks)
                    order = sort.descending ? -tailored : tailored
                } else {
                    order = Self.compareKeys(lhs.keys[index], rhs.keys[index], sort)
                }
                if order != 0 { return order < 0 }
            }
            return lhs.offset < rhs.offset
        }.map(\.node)
    }

    static func compareKeys(_ left: String, _ right: String, _ sort: PureXML.XSLT.Sort) -> Int {
        var order: Int
        if sort.numeric {
            let leftNumber = PureXML.XPath.Value.parseNumber(left)
            let rightNumber = PureXML.XPath.Value.parseNumber(right)
            // NaN keys sort before every number (the Xalan order).
            switch (leftNumber.isNaN, rightNumber.isNaN) {
            case (true, true): order = 0
            case (true, false): order = -1
            case (false, true): order = 1
            case (false, false): order = leftNumber == rightNumber ? 0 : (leftNumber < rightNumber ? -1 : 1)
            }
        } else if let caseOrder = sort.caseOrder {
            order = caseInsensitiveCompare(left, right, caseOrder)
        } else {
            order = collate(left, right)
        }
        return sort.descending ? -order : order
    }

    /// Text sort order: spaces are ignorable at the primary level (Java
    /// Collator semantics, which the conformance golds encode); when the
    /// space-stripped strings tie, the string whose first space comes later
    /// (or that has none) sorts first.
    static func collate(_ left: String, _ right: String) -> Int {
        let strippedLeft = left.filter { $0 != " " }
        let strippedRight = right.filter { $0 != " " }
        if strippedLeft != strippedRight {
            return strippedLeft < strippedRight ? -1 : 1
        }
        let leftSpaces = spacePositions(left)
        let rightSpaces = spacePositions(right)
        if leftSpaces == rightSpaces { return 0 }
        for (leftIndex, rightIndex) in zip(leftSpaces, rightSpaces) where leftIndex != rightIndex {
            return leftIndex > rightIndex ? -1 : 1
        }
        return leftSpaces.count < rightSpaces.count ? -1 : 1
    }

    private static func spacePositions(_ text: String) -> [Int] {
        text.enumerated().compactMap { $1 == " " ? $0 : nil }
    }

    /// Copies the nodes selected by `select` into the result tree (`xsl:copy-of`);
    /// a non-node-set result copies as its string value. Whole subtrees are taken
    /// as-is, so this does not recurse on their depth.
    func copyOf(_ select: String, _ context: XSLTContext) -> [ResultItem] {
        guard let nodes = value(select, context)?.nodes else {
            // A non-node-set result copies as its string value.
            return value(select, context).map { [.node(.text($0.string))] } ?? []
        }
        return nodes.map { xnode in
            switch xnode {
            case let .tree(tree): .node(Self.withInScopeNamespaces(tree))
            case let .attribute(_, attribute): .attribute(attribute)
            case let .namespace(_, prefix, uri):
                .attribute(.init(prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)", uri))
            }
        }
    }
}
