extension PureXML.XPath {
    /// Evaluates compiled steps over a node, returning the selected node-set in
    /// document order. The provided node is treated as the starting context (and,
    /// for an absolute path, as the root).
    enum Evaluator {
        static func evaluate(
            steps: [Step],
            over node: PureXML.Model.Node,
        ) throws -> [Selection] {
            guard !steps.isEmpty else { return [.node(node)] }
            var context: [PureXML.Model.Node] = [node]
            for (offset, step) in steps.enumerated() {
                if step.axis == .attribute {
                    guard offset == steps.count - 1 else { throw QueryError.attributeStepNotLast }
                    return attributeSelections(step, context: context)
                }
                var next: [PureXML.Model.Node] = []
                for contextNode in context {
                    let candidates = candidateNodes(step, contextNode)
                    next.append(contentsOf: applyPredicates(step.predicates, to: candidates))
                }
                context = next
            }
            return context.map { .node($0) }
        }

        private static func candidateNodes(_ step: Step, _ contextNode: PureXML.Model.Node) -> [PureXML.Model.Node] {
            let pool: [PureXML.Model.Node] = switch step.axis {
            case .child: children(of: contextNode)
            case .descendant: subtree(of: contextNode)
            case .selfNode: [contextNode]
            case .attribute: []
            }
            return pool.filter { matches($0, step.test) }
        }

        private static func attributeSelections(_ step: Step, context: [PureXML.Model.Node]) -> [Selection] {
            var result: [Selection] = []
            for contextNode in context {
                guard case let .element(element) = contextNode else { continue }
                var attributes = element.attributes.filter { attributeMatches($0, step.test) }
                for predicate in step.predicates {
                    if case let .position(index) = predicate {
                        attributes = (index >= 1 && index <= attributes.count) ? [attributes[index - 1]] : []
                    }
                }
                result.append(contentsOf: attributes.map { .attribute($0) })
            }
            return result
        }

        private static func applyPredicates(
            _ predicates: [Predicate],
            to nodes: [PureXML.Model.Node],
        ) -> [PureXML.Model.Node] {
            var result = nodes
            for predicate in predicates {
                switch predicate {
                case let .position(index):
                    result = (index >= 1 && index <= result.count) ? [result[index - 1]] : []
                case let .hasAttribute(name):
                    result = result.filter { attributeValue($0, name) != nil }
                case let .attributeEquals(name, value):
                    result = result.filter { attributeValue($0, name) == value }
                case let .hasChild(name):
                    result = result.filter { childElement($0, name) != nil }
                case let .childEquals(name, value):
                    result = result.filter { childElementText($0, name) == value }
                }
            }
            return result
        }

        private static func children(of node: PureXML.Model.Node) -> [PureXML.Model.Node] {
            switch node {
            case let .element(element): element.children
            case let .document(nodes): nodes
            default: []
            }
        }

        private static func subtree(of node: PureXML.Model.Node) -> [PureXML.Model.Node] {
            var result = [node]
            for child in children(of: node) {
                result.append(contentsOf: subtree(of: child))
            }
            return result
        }

        private static func matches(_ node: PureXML.Model.Node, _ test: NodeTest) -> Bool {
            switch test {
            case let .name(name):
                guard case let .element(element) = node else { return false }
                return element.name.description == name || element.name.localName == name
            case .wildcard:
                if case .element = node { return true }
                return false
            case .text:
                if case .text = node { return true }
                if case .cdata = node { return true }
                return false
            case .node:
                return true
            case .comment:
                if case .comment = node { return true }
                return false
            }
        }

        private static func attributeMatches(_ attribute: PureXML.Model.Attribute, _ test: NodeTest) -> Bool {
            switch test {
            case let .name(name): attribute.name.description == name || attribute.name.localName == name
            case .wildcard: true
            default: false
            }
        }

        private static func attributeValue(_ node: PureXML.Model.Node, _ name: String) -> String? {
            guard case let .element(element) = node else { return nil }
            return element.attributes.first { $0.name.description == name || $0.name.localName == name }?.value
        }

        private static func childElementNode(_ node: PureXML.Model.Node, _ name: String) -> PureXML.Model.Node? {
            guard case let .element(element) = node else { return nil }
            return element.children.first { child in
                if case let .element(inner) = child {
                    return inner.name.description == name || inner.name.localName == name
                }
                return false
            }
        }

        private static func childElement(_ node: PureXML.Model.Node, _ name: String) -> PureXML.Model.Element? {
            guard case let .element(found) = childElementNode(node, name) else { return nil }
            return found
        }

        private static func childElementText(_ node: PureXML.Model.Node, _ name: String) -> String? {
            guard let child = childElementNode(node, name) else { return nil }
            return Selection.node(child).stringValue
        }
    }
}
