extension PureXML.XSLT.Transformer {
    func sorted(_ nodes: [PureXML.XPath.Node], _ sorts: [PureXML.XSLT.Sort]) -> [PureXML.XPath.Node] {
        guard !sorts.isEmpty else { return nodes }
        return nodes.enumerated().sorted { lhs, rhs in
            for sort in sorts {
                let order = compareKeys(lhs.element, rhs.element, sort)
                if order != 0 { return order < 0 }
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }

    private func compareKeys(_ lhs: PureXML.XPath.Node, _ rhs: PureXML.XPath.Node, _ sort: PureXML.XSLT.Sort) -> Int {
        let left = keyValue(sort.select, lhs)
        let right = keyValue(sort.select, rhs)
        var order: Int
        if sort.numeric {
            let leftNumber = PureXML.XPath.Value.parseNumber(left)
            let rightNumber = PureXML.XPath.Value.parseNumber(right)
            order = leftNumber == rightNumber ? 0 : (leftNumber < rightNumber ? -1 : 1)
        } else if let caseOrder = sort.caseOrder {
            order = Self.caseInsensitiveCompare(left, right, caseOrder)
        } else {
            order = left == right ? 0 : (left < right ? -1 : 1)
        }
        return sort.descending ? -order : order
    }

    private func keyValue(_ expression: String, _ node: PureXML.XPath.Node) -> String {
        guard let query = try? PureXML.XPath.Query(expression) else { return "" }
        return (try? query.value(atNode: node, position: 1, size: 1, variables: [:], functions: PureXML.XPath.FunctionTable()).string) ?? ""
    }

    func forEach(
        _ select: String,
        _ sorts: [PureXML.XSLT.Sort],
        _ body: [PureXML.XSLT.Instruction],
        _ context: XSLTContext,
    ) -> [ResultItem] {
        let nodes = sorted(selectXPathNodes(select, context), sorts)
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
}
