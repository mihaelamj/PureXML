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
            return SortEntry(offset: offset, node: xnode, keys: sorts.map { string($0.select, keyContext) })
        }
        return keyed.sorted { lhs, rhs in
            for (index, sort) in sorts.enumerated() {
                let order = Self.compareKeys(lhs.keys[index], rhs.keys[index], sort)
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

    func forEach(
        _ select: String,
        _ sorts: [PureXML.XSLT.Sort],
        _ body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        let nodes = sorted(selectXPathNodes(select, context), sorts, context)
        var items: [ResultItem] = []
        for (offset, xnode) in nodes.enumerated() {
            guard let owner = Self.ownerNode(xnode) else { continue }
            let itemContext = XSLTContext(
                node: owner,
                current: xnode.treeNode == nil ? xnode : nil,
                position: offset + 1,
                size: nodes.count,
                variables: context.variables,
            )
            items += instantiate(body, itemContext)
        }
        return items
    }

    func chooseInstruction(
        _ whens: [PureXML.XSLT.Branch],
        _ otherwise: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        for branch in whens where boolean(branch.test, context) {
            return instantiate(branch.body, context)
        }
        return instantiate(otherwise, context)
    }

    func builtInRule(_ xnode: PureXML.XPath.Node, mode: String?, _ context: XSLTContext) -> [ResultItem] {
        switch xnode {
        case let .tree(node):
            switch node.kind {
            case .element, .document:
                applyTemplates(to: node.children.map { .tree($0) }, mode: mode, parameters: [], context)
            case .text, .cdata:
                [.node(.text(node.value))]
            default:
                []
            }
        case let .attribute(_, attribute):
            [.node(.text(attribute.value))]
        case let .namespace(_, _, uri):
            [.node(.text(uri))]
        }
    }

    func message(_ terminate: Bool, _ body: [PureXML.XSLT.Instruction], _ context: XSLTContext) -> [ResultItem] {
        if terminate, termination.message == nil {
            termination.message = Self.text(of: instantiate(body, context))
        }
        return []
    }

    /// Binds the template's parameters (a passed `with-param` wins over the
    /// declared default) and instantiates its body.
    func instantiateTemplate(
        _ template: PureXML.XSLT.Template,
        _ context: XSLTContext,
        passing parameters: [PureXML.XSLT.Binding],
        from caller: XSLTContext,
    ) -> [ResultItem] {
        var context = context
        context.importPrecedence = template.importPrecedence
        context.importRangeLow = template.importRangeLow
        context.namespaces = template.namespaces
        for parameter in template.parameters {
            if let passed = parameters.first(where: { $0.name == parameter.name }) {
                context.variables[parameter.name] = variableValue(passed.select, passed.body, caller)
            } else {
                context.variables[parameter.name] = variableValue(parameter.select, parameter.body, context)
            }
        }
        return instantiate(template.body, context)
    }
}
