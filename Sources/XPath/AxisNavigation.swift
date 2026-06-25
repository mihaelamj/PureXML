extension PureXML.XPath {
    /// Produces the nodes reachable from a context node along an axis, before any
    /// node test or predicate. Forward axes come back in document order and
    /// reverse axes nearest-first, so positional predicates number correctly.
    enum AxisNavigation {
        private static let xmlNamespaceURI = "http://www.w3.org/XML/1998/namespace"

        static func nodes(
            on axis: Axis,
            from context: Node,
            cache: DocumentNavigationCache? = nil,
            siblingCache: SiblingIndexCache? = nil,
        ) -> [Node] {
            verticalNodes(on: axis, from: context)
                ?? lateralNodes(on: axis, from: context, cache: cache, siblingCache: siblingCache)
        }

        /// The self, child, descendant, parent, and ancestor families; nil for an
        /// axis handled by ``lateralNodes(on:from:)``.
        private static func verticalNodes(on axis: Axis, from context: Node) -> [Node]? {
            switch axis {
            case .child: children(of: context)
            case .descendant: descendants(of: context)
            case .descendantOrSelf: descendantsOrSelf(of: context)
            case .parent: context.parent.map { [$0] } ?? []
            case .ancestor: ancestors(of: context)
            case .ancestorOrSelf: [context] + ancestors(of: context)
            case .selfAxis: [context]
            default: nil
            }
        }

        /// The sibling, following/preceding, attribute, and namespace axes.
        private static func lateralNodes(
            on axis: Axis,
            from context: Node,
            cache: DocumentNavigationCache?,
            siblingCache: SiblingIndexCache?,
        ) -> [Node] {
            switch axis {
            case .followingSibling: followingSiblings(of: context, siblingCache: siblingCache, where: { _ in true })
            case .precedingSibling: precedingSiblings(of: context, siblingCache: siblingCache, where: { _ in true })
            case .following: following(of: context, cache: cache, where: { _ in true })
            case .preceding: preceding(of: context, cache: cache, where: { _ in true })
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
            guard case let .tree(tree) = node else { return [] }
            var result: [Node] = []
            appendDescendants(of: tree, into: &result)
            return result
        }

        static func descendantsOrSelf(of node: Node) -> [Node] {
            guard case let .tree(tree) = node else { return [node] }
            var result: [Node] = [node]
            appendDescendants(of: tree, into: &result)
            return result
        }

        /// Appends every descendant of `tree` in document order through a single
        /// shared accumulator. Recursing on the raw ``TreeNode`` rather than on a
        /// wrapped ``Node`` means the traversal builds no intermediate per-level
        /// arrays and wraps each node exactly once, when it is appended.
        private static func appendDescendants(of tree: PureXML.Model.TreeNode, into result: inout [Node]) {
            for child in tree.children {
                result.append(.tree(child))
                appendDescendants(of: child, into: &result)
            }
        }

        /// The descendants of `tree` that satisfy `keep`, in document order. The
        /// whole subtree is still traversed (every node may have matching
        /// descendants), but a node `keep` rejects is never wrapped in a ``Node``,
        /// so it is never retained. This fuses a step's node test into the axis
        /// walk, the common case being `descendant::name` over a wide subtree
        /// where most nodes do not match.
        static func descendants(of tree: PureXML.Model.TreeNode, where keep: (PureXML.Model.TreeNode) -> Bool) -> [Node] {
            var result: [Node] = []
            appendDescendants(of: tree, where: keep, into: &result)
            return result
        }

        /// `descendant-or-self` with a `keep` filter: the context node itself is
        /// tested first, then its descendants.
        static func descendantsOrSelf(of tree: PureXML.Model.TreeNode, where keep: (PureXML.Model.TreeNode) -> Bool) -> [Node] {
            var result: [Node] = []
            if keep(tree) { result.append(.tree(tree)) }
            appendDescendants(of: tree, where: keep, into: &result)
            return result
        }

        private static func appendDescendants(
            of tree: PureXML.Model.TreeNode,
            where keep: (PureXML.Model.TreeNode) -> Bool,
            into result: inout [Node],
        ) {
            for child in tree.children {
                if keep(child) { result.append(.tree(child)) }
                appendDescendants(of: child, where: keep, into: &result)
            }
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

        /// The following-sibling axis, fusing the step's node test into the walk:
        /// the raw child ``TreeNode`` is tested before it is wrapped, so a sibling
        /// the test rejects is never wrapped (and never retained). The unfused
        /// caller passes a test that keeps everything.
        static func followingSiblings(of node: Node, siblingCache: SiblingIndexCache?, where keep: (PureXML.Model.TreeNode) -> Bool) -> [Node] {
            guard let (parent, index) = siblingPosition(of: node, cache: siblingCache) else { return [] }
            return parent.children[(index + 1)...].compactMap { keep($0) ? Node.tree($0) : nil }
        }

        /// The preceding-sibling axis (nearest first), with the same node-test
        /// fusion as ``followingSiblings(of:siblingCache:where:)``.
        static func precedingSiblings(of node: Node, siblingCache: SiblingIndexCache?, where keep: (PureXML.Model.TreeNode) -> Bool) -> [Node] {
            guard let (parent, index) = siblingPosition(of: node, cache: siblingCache) else { return [] }
            return parent.children[..<index].reversed().compactMap { keep($0) ? Node.tree($0) : nil }
        }

        /// The following axis, fusing the step's node test into the walk: `keep`
        /// is applied to the document-order slice directly, so a node the test
        /// rejects is never copied out of the shared node list (only matches are
        /// materialized). The unfused caller passes a test that keeps everything.
        static func following(of node: Node, cache: DocumentNavigationCache?, where keep: (Node) -> Bool) -> [Node] {
            guard let root = rootTree(of: node) else { return [] }
            let document = orderedDocument(rootedAt: root, cache: cache)
            if let index = document.index[node] {
                // A node's descendants are the contiguous block right after it in
                // document order, so the following axis begins just past the
                // subtree. Skip it by index rather than scanning the whole tail
                // and filtering each descendant out (which made this quadratic).
                let start = index + 1 + descendantCount(of: node)
                return start < document.nodes.count ? document.nodes[start...].filter(keep) : []
            }
            // An attribute or namespace start: document order places it after
            // its owner and before the owner's children, and it has no
            // descendants, so everything after the owner follows.
            guard let owner = node.parent, let index = document.index[owner] else { return [] }
            return document.nodes[(index + 1)...].filter(keep)
        }

        /// The preceding axis, fusing the step's node test into the walk: the
        /// span before the context is filtered by `keep` (and the ancestors,
        /// which the axis excludes) in one pass, so only matches are materialized.
        static func preceding(of node: Node, cache: DocumentNavigationCache?, where keep: (Node) -> Bool) -> [Node] {
            guard let root = rootTree(of: node) else { return [] }
            let document = orderedDocument(rootedAt: root, cache: cache)
            let anchorIndex = document.index[node] ?? node.parent.flatMap { document.index[$0] }
            guard let index = anchorIndex else { return [] }
            // The excluded ancestors are few (the depth), so a membership filter
            // over the preceding span is fine; the win here is the cached node
            // list and the O(1) anchor lookup instead of a rebuild and scan.
            let excluded = Set(ancestors(of: node))
            return document.nodes[..<index].filter { !excluded.contains($0) && keep($0) }.reversed()
        }

        /// The number of tree-node descendants of `node`, matching what the
        /// document node list counts after it (attribute and namespace nodes are
        /// not in that list, so they are not counted).
        private static func descendantCount(of node: Node) -> Int {
            guard case let .tree(tree) = node else { return 0 }
            return subtreeNodeCount(tree) - 1
        }

        private static func subtreeNodeCount(_ tree: PureXML.Model.TreeNode) -> Int {
            var count = 1
            for child in tree.children {
                count += subtreeNodeCount(child)
            }
            return count
        }

        /// The document's nodes in document order plus a node-to-index map, built
        /// once per document root and reused across the following and preceding
        /// evaluations of one query.
        private static func orderedDocument(
            rootedAt root: PureXML.Model.TreeNode,
            cache: DocumentNavigationCache?,
        ) -> (nodes: [Node], index: [Node: Int]) {
            if let cache, let hit = cache.byRoot[ObjectIdentifier(root)] { return hit }
            var nodes: [Node] = []
            appendSubtree(root, into: &nodes)
            var index: [Node: Int] = [:]
            index.reserveCapacity(nodes.count)
            for (offset, node) in nodes.enumerated() {
                index[node] = offset
            }
            let entry = (nodes: nodes, index: index)
            cache?.byRoot[ObjectIdentifier(root)] = entry
            return entry
        }

        private static func attributes(of node: Node) -> [Node] {
            guard case let .tree(tree) = node, tree.kind == .element else { return [] }
            return tree.attributes
                .filter { !isNamespaceDeclaration($0) }
                .map { Node.attribute(owner: tree, $0) }
        }

        /// The attributes of `tree` that satisfy `keep`, in declaration order. An
        /// attribute `keep` rejects is never wrapped in a ``Node``, so it is never
        /// retained (each wrap retains the owner and copies the attribute's
        /// qualified name and value). This fuses a step's node test into the
        /// attribute walk, the common case being `@name` selecting one of several
        /// attributes (as in a `[@x='y']` predicate).
        static func attributes(of tree: PureXML.Model.TreeNode, where keep: (PureXML.Model.Attribute) -> Bool) -> [Node] {
            guard tree.kind == .element else { return [] }
            var result: [Node] = []
            for attribute in tree.attributes where !isNamespaceDeclaration(attribute) && keep(attribute) {
                result.append(.attribute(owner: tree, attribute))
            }
            return result
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

        private static func siblingPosition(of node: Node, cache: SiblingIndexCache?) -> (PureXML.Model.TreeNode, Int)? {
            guard case let .tree(tree) = node, let parent = tree.parent else { return nil }
            // A node is always among its parent's children, so the cache's index
            // is exact; without one, scanning the sibling list per node makes the
            // sibling axes quadratic over a wide parent.
            if let cache {
                return (parent, cache.index(of: tree, in: parent))
            }
            guard let index = parent.children.firstIndex(where: { $0 === tree }) else { return nil }
            return (parent, index)
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

    /// A per-query cache of each document's ordered node list and node-to-index
    /// map, for the following and preceding axes. Without it those axes rebuild
    /// the whole node list and linearly search it on every context node, which is
    /// quadratic over a wide document. The document does not change during an
    /// evaluation, so caching by root identity is safe.
    final class DocumentNavigationCache {
        fileprivate var byRoot: [ObjectIdentifier: (nodes: [Node], index: [Node: Int])] = [:]

        init() {}
    }
}
