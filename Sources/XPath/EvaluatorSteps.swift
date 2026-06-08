extension PureXML.XPath.Evaluator {
    typealias Node = PureXML.XPath.Node
    typealias Step = PureXML.XPath.Step
    typealias NodeTest = PureXML.XPath.NodeTest
    typealias Axis = PureXML.XPath.Axis
    typealias Expression = PureXML.XPath.Expression
    typealias EvaluationContext = PureXML.XPath.EvaluationContext
    typealias Value = PureXML.XPath.Value
    typealias PrincipalKind = PureXML.XPath.PrincipalKind

    /// Walks the steps from a starting node-set, threading each step's result into
    /// the next. Predicates run with proximity position within each context node's
    /// axis result.
    static func evaluateSteps(_ steps: [Step], from start: [Node], _ context: EvaluationContext) -> [Node] {
        var current = start
        for step in steps {
            var result: [Node] = []
            var seen: Set<Node> = []
            for contextNode in current {
                let matched = PureXML.XPath.AxisNavigation.nodes(on: step.axis, from: contextNode)
                    .filter { matches($0, step.test, on: step.axis) }
                let filtered = (try? applyPredicates(step.predicates, to: matched, context)) ?? matched
                for node in filtered where seen.insert(node).inserted {
                    result.append(node)
                }
            }
            current = result
        }
        return current
    }

    /// Filters nodes through each predicate in turn. A numeric predicate is a
    /// position test; any other is taken as a boolean.
    static func applyPredicates(
        _ predicates: [Expression],
        to nodes: [Node],
        _ context: EvaluationContext,
    ) throws -> [Node] {
        var current = nodes
        for predicate in predicates {
            var kept: [Node] = []
            let size = current.count
            for (offset, node) in current.enumerated() {
                let focused = context.focused(on: node, position: offset + 1, size: size)
                if try keeps(predicate, focused, position: offset + 1) {
                    kept.append(node)
                }
            }
            current = kept
        }
        return current
    }

    private static func keeps(_ predicate: Expression, _ context: EvaluationContext, position: Int) throws -> Bool {
        let value = try eval(predicate, context)
        if case let .number(number) = value {
            return Int(number) == position
        }
        return value.boolean
    }

    // MARK: Node tests

    static func matches(_ node: Node, _ test: NodeTest, on axis: Axis) -> Bool {
        switch test {
        case let .name(name):
            nameMatches(node, name, axis.principalKind)
        case .wildcard:
            wildcardMatches(node, axis.principalKind)
        case .text:
            isTreeKind(node, in: [.text, .cdata])
        case .node:
            true
        case .comment:
            isTreeKind(node, in: [.comment])
        case let .processingInstruction(target):
            processingInstructionMatches(node, target)
        }
    }

    private static func nameMatches(_ node: Node, _ name: String, _ kind: PrincipalKind) -> Bool {
        switch kind {
        case .element:
            guard case let .tree(tree) = node, tree.kind == .element, let qualified = tree.name else {
                return false
            }
            return qualified.description == name || qualified.localName == name
        case .attribute:
            guard case let .attribute(_, attribute) = node else { return false }
            return attribute.name.description == name || attribute.name.localName == name
        case .namespace:
            guard case let .namespace(_, prefix, _) = node else { return false }
            return prefix == name
        }
    }

    private static func wildcardMatches(_ node: Node, _ kind: PrincipalKind) -> Bool {
        switch kind {
        case .element: return isTreeKind(node, in: [.element])
        case .attribute: if case .attribute = node { return true }
            return false
        case .namespace: if case .namespace = node { return true }
            return false
        }
    }

    private static func processingInstructionMatches(_ node: Node, _ target: String?) -> Bool {
        guard case let .tree(tree) = node, tree.kind == .processingInstruction else { return false }
        guard let target else { return true }
        return tree.name?.description == target
    }

    private static func isTreeKind(_ node: Node, in kinds: [PureXML.Model.TreeNodeKind]) -> Bool {
        guard case let .tree(tree) = node else { return false }
        return kinds.contains(tree.kind)
    }
}
