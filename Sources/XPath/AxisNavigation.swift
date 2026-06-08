extension PureXML.XPath {
    /// Produces the nodes reachable from a context node along an axis, before any
    /// node test or predicate. Forward axes come back in document order and
    /// reverse axes nearest-first, so positional predicates number correctly.
    enum AxisNavigation {
        private static let xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace"

        static func nodes(on axis: Axis, from context: Node) -> [Node] {
            verticalNodes(on: axis, from: context) ?? lateralNodes(on: axis, from: context)
        }

        /// The self, child, descendant, parent, and ancestor families; nil for an
        /// axis handled by ``lateralNodes(on:from:)``.
        private static func verticalNodes(on axis: Axis, from context: Node) -> [Node]? {
            switch axis {
            case .child: children(of: context)
            case .descendant: descendants(of: context)
            case .descendantOrSelf: [context] + descendants(of: context)
            case .parent: context.parent.map { [$0] } ?? []
            case .ancestor: ancestors(of: context)
            case .ancestorOrSelf: [context] + ancestors(of: context)
            case .selfAxis: [context]
            default: nil
            }
        }

        /// The sibling, following/preceding, attribute, and namespace axes.
        private static func lateralNodes(on axis: Axis, from context: Node) -> [Node] {
            switch axis {
            case .followingSibling: followingSiblings(of: context)
            case .precedingSibling: precedingSiblings(of: context)
            case .following: following(of: context)
            case .preceding: preceding(of: context)
            case .attribute: attributes(of: context)
            case .namespace: namespaces(of: context)
            default: []
            }
        }

        static func children(of node: Node) -> [Node] {
            guard case let .tree(tree) = node else { return [] }
            return tree.children.map(Node.tree)
        }

        static func descendants(of node: Node) -> [Node] {
            var result: [Node] = []
            for child in children(of: node) {
                result.append(child)
                result.append(contentsOf: descendants(of: child))
            }
            return result
        }

        static func ancestors(of node: Node) -> [Node] {
            var result: [Node] = []
            var current = node.parent
            while let ancestor = current {
                result.append(ancestor)
                current = ancestor.parent
            }
            return result
        }

        private static func followingSiblings(of node: Node) -> [Node] {
            guard let (parent, index) = siblingPosition(of: node) else { return [] }
            return parent.children[(index + 1)...].map(Node.tree)
        }

        private static func precedingSiblings(of node: Node) -> [Node] {
            guard let (parent, index) = siblingPosition(of: node) else { return [] }
            return parent.children[..<index].reversed().map(Node.tree)
        }

        private static func following(of node: Node) -> [Node] {
            let all = documentNodes(of: node)
            guard let index = all.firstIndex(of: node) else { return [] }
            let excluded = Set(descendants(of: node))
            return all[(index + 1)...].filter { !excluded.contains($0) }
        }

        private static func preceding(of node: Node) -> [Node] {
            let all = documentNodes(of: node)
            guard let index = all.firstIndex(of: node) else { return [] }
            let excluded = Set(ancestors(of: node))
            return all[..<index].filter { !excluded.contains($0) }.reversed()
        }

        private static func attributes(of node: Node) -> [Node] {
            guard case let .tree(tree) = node, tree.kind == .element else { return [] }
            return tree.attributes
                .filter { !isNamespaceDeclaration($0) }
                .map { Node.attribute(owner: tree, $0) }
        }

        private static func namespaces(of node: Node) -> [Node] {
            guard case let .tree(tree) = node, tree.kind == .element else { return [] }
            var bindings: [String: String] = ["xml": xmlNamespaceURI]
            var current: PureXML.Model.TreeNode? = tree
            while let element = current {
                if element.kind == .element {
                    collectBindings(from: element, into: &bindings)
                }
                current = element.parent
            }
            return bindings.compactMap { prefix, uri in
                uri.isEmpty ? nil : Node.namespace(owner: tree, prefix: prefix, uri: uri)
            }
        }

        private static func collectBindings(
            from element: PureXML.Model.TreeNode,
            into bindings: inout [String: String],
        ) {
            for attribute in element.attributes {
                let name = attribute.name
                if name.prefix == nil, name.localName == "xmlns" {
                    if bindings[""] == nil { bindings[""] = attribute.value }
                } else if name.prefix == "xmlns", bindings[name.localName] == nil {
                    bindings[name.localName] = attribute.value
                }
            }
        }

        private static func isNamespaceDeclaration(_ attribute: PureXML.Model.Attribute) -> Bool {
            let name = attribute.name
            return name.prefix == "xmlns" || (name.prefix == nil && name.localName == "xmlns")
        }

        private static func siblingPosition(of node: Node) -> (PureXML.Model.TreeNode, Int)? {
            guard case let .tree(tree) = node, let parent = tree.parent else { return nil }
            guard let index = parent.children.firstIndex(where: { $0 === tree }) else { return nil }
            return (parent, index)
        }

        /// Every tree node of the containing document, in document order. Used to
        /// derive the following and preceding axes by position.
        private static func documentNodes(of node: Node) -> [Node] {
            guard let root = rootTree(of: node) else { return [] }
            var result: [Node] = []
            appendSubtree(root, into: &result)
            return result
        }

        private static func appendSubtree(_ tree: PureXML.Model.TreeNode, into result: inout [Node]) {
            result.append(.tree(tree))
            for child in tree.children {
                appendSubtree(child, into: &result)
            }
        }

        private static func rootTree(of node: Node) -> PureXML.Model.TreeNode? {
            let start: PureXML.Model.TreeNode? = switch node {
            case let .tree(tree): tree
            case let .attribute(owner, _), let .namespace(owner, _, _): owner
            }
            guard var current = start else { return nil }
            while let parent = current.parent {
                current = parent
            }
            return current
        }
    }
}
