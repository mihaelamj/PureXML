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
    static func evaluateSteps(_ steps: [Step], from start: [Node], _ context: EvaluationContext) throws -> [Node] {
        var current = start
        for step in steps {
            var result: [Node] = []
            // Cross-context de-duplication is needed only when two distinct
            // context nodes can reach the same node. With at most one context, or
            // on an axis whose results are disjoint per context (child, attribute,
            // namespace, self), no duplicate can arise, so accumulate directly:
            // the `Set` path below produces the identical sequence (every insert
            // succeeds) at the cost of hashing and copying every node.
            if current.count <= 1 || step.axis.yieldsDisjointResults {
                for contextNode in current {
                    try result.append(contentsOf: stepNodes(step, from: contextNode, context))
                    try context.checkBudget(result.count)
                }
            } else {
                var seen: Set<Node> = []
                for contextNode in current {
                    for node in try stepNodes(step, from: contextNode, context) where seen.insert(node).inserted {
                        result.append(node)
                    }
                    try context.checkBudget(result.count)
                }
            }
            current = result
        }
        return current
    }

    /// The nodes a single `step` selects from one `contextNode`: the axis nodes
    /// that pass the node test, then the step's predicates (applied per context,
    /// as XPath proximity position requires).
    private static func stepNodes(_ step: Step, from contextNode: Node, _ context: EvaluationContext) throws -> [Node] {
        let matched = matchedAxisNodes(step, from: contextNode, context)
        return try applyPredicates(step.predicates, to: matched, context)
    }

    /// The axis nodes that pass the step's node test. For the descendant family
    /// over a tree context the test is fused into the traversal so a node the
    /// test rejects is never wrapped (and so never retained); every other axis
    /// builds the axis node list and filters it.
    private static func matchedAxisNodes(_ step: Step, from contextNode: Node, _ context: EvaluationContext) -> [Node] {
        if case let .tree(tree) = contextNode {
            switch step.axis {
            case .descendant:
                return PureXML.XPath.AxisNavigation.descendants(of: tree) { matchesTree($0, step.test, on: step.axis, context.namespaces) }
            case .descendantOrSelf:
                return PureXML.XPath.AxisNavigation.descendantsOrSelf(of: tree) { matchesTree($0, step.test, on: step.axis, context.namespaces) }
            case .attribute:
                return PureXML.XPath.AxisNavigation.attributes(of: tree) { matchesAttribute($0, step.test, context.namespaces) }
            default: break
            }
        }
        return PureXML.XPath.AxisNavigation.nodes(on: step.axis, from: contextNode)
            .filter { matches($0, step.test, on: step.axis, namespaces: context.namespaces) }
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

    static func matches(_ node: Node, _ test: NodeTest, on axis: Axis, namespaces: [String: String] = [:]) -> Bool {
        if case let .tree(tree) = node {
            return matchesTree(tree, test, on: axis, namespaces)
        }
        // Attribute and namespace nodes: a name or wildcard test selects them
        // (by the axis's principal kind), `node()` matches anything, and the
        // kind tests (text/comment/processing-instruction) never match a node
        // that is not a tree node.
        switch test {
        case let .name(name): return nameMatches(node, name, axis.principalKind, namespaces)
        case .wildcard: return wildcardMatches(node, axis.principalKind)
        case .node: return true
        case .text, .comment, .processingInstruction: return false
        }
    }

    /// The node test applied directly to an attribute, the single-node core of
    /// ``matches`` for an `.attribute` node on the attribute axis (whose
    /// principal kind is always attribute). Taking the raw ``Attribute`` lets the
    /// attribute axis test a candidate without wrapping (and so retaining) it, so
    /// an attribute the test rejects is never materialized. A name test matches
    /// by qualified name; a wildcard or `node()` matches any attribute; the kind
    /// tests never match an attribute.
    static func matchesAttribute(_ attribute: PureXML.Model.Attribute, _ test: NodeTest, _ namespaces: [String: String]) -> Bool {
        switch test {
        case let .name(name): qualifiedMatches(attribute.name, name, namespaces)
        case .wildcard, .node: true
        case .text, .comment, .processingInstruction: false
        }
    }

    /// The node test applied directly to a tree node, the single-node core of
    /// ``matches`` for a `.tree` node. Taking the ``TreeNode`` rather than a
    /// wrapped ``Node`` lets the descendant traversal test a candidate without
    /// first wrapping (and so retaining) it, so a node the test rejects is never
    /// retained. ``matches`` delegates here for every tree node, keeping one
    /// source of truth.
    static func matchesTree(_ tree: PureXML.Model.TreeNode, _ test: NodeTest, on axis: Axis, _ namespaces: [String: String]) -> Bool {
        switch test {
        case let .name(name):
            guard axis.principalKind == .element, tree.kind == .element, let qualified = tree.name else { return false }
            return qualifiedMatches(qualified, name, namespaces)
        case .wildcard:
            return axis.principalKind == .element && tree.kind == .element
        case .text:
            return tree.kind == .text || tree.kind == .cdata
        case .node:
            return true
        case .comment:
            return tree.kind == .comment
        case let .processingInstruction(target):
            guard tree.kind == .processingInstruction else { return false }
            return target == nil || tree.name?.description == target
        }
    }

    private static func nameMatches(_ node: Node, _ name: String, _ kind: PrincipalKind, _ namespaces: [String: String]) -> Bool {
        switch kind {
        case .element:
            guard case let .tree(tree) = node, tree.kind == .element, let qualified = tree.name else {
                return false
            }
            return qualifiedMatches(qualified, name, namespaces)
        case .attribute:
            guard case let .attribute(_, attribute) = node else { return false }
            return qualifiedMatches(attribute.name, name, namespaces)
        case .namespace:
            guard case let .namespace(_, prefix, _) = node else { return false }
            return prefix == name
        }
    }

    /// Matches a node's qualified name against a test name. When an eval-time
    /// prefix binding covers the test's prefix, the match is by namespace URI and
    /// local name; otherwise it falls back to the in-document prefix string (the
    /// behavior when no bindings are supplied).
    private static func qualifiedMatches(_ qualified: PureXML.Model.QualifiedName, _ name: String, _ namespaces: [String: String]) -> Bool {
        if !namespaces.isEmpty {
            if let colon = name.firstIndex(of: ":") {
                let prefix = String(name[..<colon])
                if let uri = namespaces[prefix] {
                    let local = String(name[name.index(after: colon)...])
                    // The NCName:* form matches every name in the namespace.
                    if local == "*" { return (qualified.namespaceURI ?? "") == uri }
                    return qualified.localName == local && (qualified.namespaceURI ?? "") == uri
                }
            } else {
                // With bindings supplied, the XPath 1.0 rule applies exactly:
                // an unprefixed name test selects the null namespace.
                return qualified.localName == name && (qualified.namespaceURI ?? "").isEmpty
            }
        }
        if name.hasSuffix(":*"), let colon = name.firstIndex(of: ":") {
            // Without bindings the prefix-wildcard falls back to the
            // in-document prefix string, like plain prefixed tests.
            return qualified.prefix == String(name[..<colon])
        }
        return qualified.description == name || qualified.localName == name
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
