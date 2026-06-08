extension PureXML.XPath {
    /// Evaluates compiled steps over a node, returning the selected node-set in
    /// document order. The provided node is the starting context and, for an
    /// absolute path, the root.
    enum Evaluator {
        static func evaluate(
            steps: [Step],
            over node: PureXML.Model.Node,
        ) -> [Selection] {
            let root = PureXML.Model.TreeNode(node)
            var context: [Node] = [.tree(root)]
            for step in steps {
                context = self.step(step, over: context)
            }
            return order(context).map(selection)
        }

        private static func step(_ step: Step, over context: [Node]) -> [Node] {
            var result: [Node] = []
            var seen: Set<Node> = []
            for contextNode in context {
                let axisNodes = AxisNavigation.nodes(on: step.axis, from: contextNode)
                    .filter { matches($0, step.test, on: step.axis) }
                for node in applyPredicates(step.predicates, to: axisNodes) where seen.insert(node).inserted {
                    result.append(node)
                }
            }
            return result
        }

        // MARK: Node tests

        private static func matches(_ node: Node, _ test: NodeTest, on axis: Axis) -> Bool {
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

        // MARK: Predicates

        private static func applyPredicates(_ predicates: [Predicate], to nodes: [Node]) -> [Node] {
            var result = nodes
            for predicate in predicates {
                result = apply(predicate, to: result)
            }
            return result
        }

        private static func apply(_ predicate: Predicate, to nodes: [Node]) -> [Node] {
            switch predicate {
            case let .position(index):
                (index >= 1 && index <= nodes.count) ? [nodes[index - 1]] : []
            case let .hasAttribute(name):
                nodes.filter { attributeValue($0, name) != nil }
            case let .attributeEquals(name, value):
                nodes.filter { attributeValue($0, name) == value }
            case let .hasChild(name):
                nodes.filter { childElement($0, name) != nil }
            case let .childEquals(name, value):
                nodes.filter { childElement($0, name)?.stringValue == value }
            }
        }

        private static func attributeValue(_ node: Node, _ name: String) -> String? {
            guard case let .tree(tree) = node, tree.kind == .element else { return nil }
            return tree.attributes.first { $0.name.description == name || $0.name.localName == name }?.value
        }

        private static func childElement(_ node: Node, _ name: String) -> PureXML.Model.TreeNode? {
            guard case let .tree(tree) = node else { return nil }
            return tree.children.first { child in
                child.kind == .element && (child.name?.description == name || child.name?.localName == name)
            }
        }

        // MARK: Result ordering and mapping

        private static func order(_ nodes: [Node]) -> [Node] {
            nodes.sorted(by: Node.precedes)
        }

        private static func selection(_ node: Node) -> Selection {
            switch node {
            case let .tree(tree):
                return .node(tree.node)
            case let .attribute(_, attribute):
                return .attribute(attribute)
            case let .namespace(_, prefix, uri):
                let name = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)"
                return .attribute(PureXML.Model.Attribute(name, uri))
            }
        }
    }
}
