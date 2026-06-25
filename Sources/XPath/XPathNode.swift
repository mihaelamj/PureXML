public extension PureXML.XPath {
    /// An XPath node. Most nodes wrap a parent-aware ``PureXML/Model/TreeNode``
    /// (element, text, CDATA, comment, processing instruction, or the document
    /// root). Attributes and namespaces are not tree nodes, so XPath surfaces them
    /// as nodes owned by their element, as the data model requires.
    ///
    /// Equality and hashing are by identity: two wrappers of the same tree node,
    /// attribute, or namespace compare equal, which is what node-set de-duplication
    /// needs. ``documentOrder`` gives the total order XPath results are sorted into.
    enum Node: Hashable {
        case tree(PureXML.Model.TreeNode)
        case attribute(owner: PureXML.Model.TreeNode, PureXML.Model.Attribute)
        case namespace(owner: PureXML.Model.TreeNode, prefix: String, uri: String)

        public static func == (lhs: Node, rhs: Node) -> Bool {
            switch (lhs, rhs) {
            case let (.tree(left), .tree(right)):
                left === right
            case let (.attribute(leftOwner, left), .attribute(rightOwner, right)):
                leftOwner === rightOwner && left.name == right.name
            case let (.namespace(leftOwner, leftPrefix, _), .namespace(rightOwner, rightPrefix, _)):
                leftOwner === rightOwner && leftPrefix == rightPrefix
            default:
                false
            }
        }

        public func hash(into hasher: inout Hasher) {
            switch self {
            case let .tree(node):
                hasher.combine(0)
                hasher.combine(ObjectIdentifier(node))
            case let .attribute(owner, attribute):
                hasher.combine(1)
                hasher.combine(ObjectIdentifier(owner))
                hasher.combine(attribute.name)
            case let .namespace(owner, prefix, _):
                hasher.combine(2)
                hasher.combine(ObjectIdentifier(owner))
                hasher.combine(prefix)
            }
        }

        /// The wrapped tree node, when this is one (nil for attribute/namespace).
        var treeNode: PureXML.Model.TreeNode? {
            guard case let .tree(node) = self else { return nil }
            return node
        }

        /// The owning element of an attribute or namespace node, or the tree
        /// node's own parent for a tree node.
        var parent: Node? {
            switch self {
            case let .tree(node):
                node.parent.map(Node.tree)
            case let .attribute(owner, _), let .namespace(owner, _, _):
                .tree(owner)
            }
        }

        /// The XPath string-value: an attribute's value, a namespace URI, or the
        /// concatenated character data of a tree node's subtree.
        var stringValue: String {
            switch self {
            case let .tree(node):
                node.stringValue
            case let .attribute(_, attribute):
                attribute.value
            case let .namespace(_, _, uri):
                uri
            }
        }

        /// The node's expanded name, or nil for nodes without a name (text, CDATA,
        /// comment, document). For a namespace node the local part is the prefix.
        var qualifiedName: PureXML.Model.QualifiedName? {
            switch self {
            case let .tree(node):
                switch node.kind {
                case .element, .processingInstruction:
                    node.name
                default:
                    nil
                }
            case let .attribute(_, attribute):
                attribute.name
            case let .namespace(_, prefix, _):
                PureXML.Model.QualifiedName(prefix)
            }
        }

        /// The path of child indices from the document root, with negative bands
        /// placing namespace nodes before attribute nodes before child nodes, so a
        /// lexicographic compare yields XPath document order.
        var documentOrder: [Int] {
            switch self {
            case let .tree(node):
                return Self.treePath(node)
            case let .attribute(owner, attribute):
                let index = owner.attributes.firstIndex { $0.name == attribute.name } ?? 0
                return Self.treePath(owner) + [Self.attributeBand, index]
            case let .namespace(owner, prefix, _):
                return Self.treePath(owner) + [Self.namespaceBand, prefix.hashValue]
            }
        }

        private static let namespaceBand = -2
        private static let attributeBand = -1

        private static func treePath(_ node: PureXML.Model.TreeNode) -> [Int] {
            treePath(node, cache: nil)
        }

        /// The root path, with an optional per-operation sibling-index cache:
        /// without one, finding a node's index among its siblings is linear,
        /// which turns a sort over a flat fan-out (one parent, n children)
        /// quadratic. The cache enumerates each distinct parent once, making
        /// total key computation linear in the tree.
        static func treePath(_ node: PureXML.Model.TreeNode, cache: SiblingIndexCache?) -> [Int] {
            var path: [Int] = []
            var current = node
            while let parent = current.parent {
                path.append(cache?.index(of: current, in: parent) ?? parent.children.firstIndex { $0 === current } ?? 0)
                current = parent
            }
            return path.reversed()
        }

        /// `documentOrder` with the sibling-index cache applied.
        func documentOrder(cache: SiblingIndexCache) -> [Int] {
            switch self {
            case let .tree(node):
                return Self.treePath(node, cache: cache)
            case let .attribute(owner, attribute):
                let index = owner.attributes.firstIndex { $0.name == attribute.name } ?? 0
                return Self.treePath(owner, cache: cache) + [Self.attributeBand, index]
            case let .namespace(owner, prefix, _):
                return Self.treePath(owner, cache: cache) + [Self.namespaceBand, prefix.hashValue]
            }
        }

        /// Whether `lhs` precedes `rhs` in document order. Each call recomputes
        /// both order keys; for sorts and minimums over node-sets, prefer
        /// ``Swift/Sequence/sortedByDocumentOrder()`` and
        /// ``Swift/Sequence/firstInDocumentOrder()``, which compute each key once.
        static func precedes(_ lhs: Node, _ rhs: Node) -> Bool {
            ordered(lhs.documentOrder, before: rhs.documentOrder)
        }

        /// Lexicographic compare of two document-order keys.
        static func ordered(_ left: [Int], before right: [Int]) -> Bool {
            for (one, two) in zip(left, right) where one != two {
                return one < two
            }
            return left.count < right.count
        }
    }
}

extension Sequence<PureXML.XPath.Node> {
    /// The nodes sorted into document order, computing each node's order key once
    /// (decorate-sort-undecorate) rather than recomputing the root path on every
    /// comparison, which turns an O(n log n x depth) sort into O(n log n).
    func sortedByDocumentOrder() -> [PureXML.XPath.Node] {
        // Zero- and one-node sets are already sorted: the common predicate
        // case must not touch order keys at all.
        let nodes = Array(self)
        if nodes.count <= 1 { return nodes }
        let cache = PureXML.XPath.SiblingIndexCache()
        return nodes.map { (node: $0, key: $0.documentOrder(cache: cache)) }
            .sorted { PureXML.XPath.Node.ordered($0.key, before: $1.key) }
            .map(\.node)
    }

    /// The first node in document order, computing each node's order key once.
    func firstInDocumentOrder() -> PureXML.XPath.Node? {
        let nodes = Array(self)
        // Zero or one node needs no ordering: the single node is trivially first.
        // This is the common case for string-value extraction (`string(@x)`,
        // `value-of`), where computing a document-order key would needlessly scan
        // the node's siblings, turning a flat fan-out quadratic.
        guard nodes.count > 1 else { return nodes.first }
        let cache = PureXML.XPath.SiblingIndexCache()
        return nodes.map { (node: $0, key: $0.documentOrder(cache: cache)) }
            .min { PureXML.XPath.Node.ordered($0.key, before: $1.key) }?
            .node
    }
}
