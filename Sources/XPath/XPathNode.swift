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
                let index = cache.attributeIndex(of: attribute.name, in: owner)
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
    /// The nodes sorted into XPath document order. Keys come from a per-root
    /// pre-order index (see ``PureXML/XPath/AxisNavigation/sortByDocumentOrder(_:cache:)``),
    /// so the sort is linear in the document rather than O(n log n x depth): a
    /// per-node root path made this quadratic on a deeply-nested document.
    /// Passing the evaluation's shared `cache` builds each document's index once
    /// and reuses it across every sort in the query.
    func sortedByDocumentOrder(cache: PureXML.XPath.DocumentNavigationCache? = nil) -> [PureXML.XPath.Node] {
        PureXML.XPath.AxisNavigation.sortByDocumentOrder(Array(self), cache: cache)
    }

    /// The first node in document order, by the same keying as
    /// ``sortedByDocumentOrder(cache:)`` but without a full sort.
    func firstInDocumentOrder(cache: PureXML.XPath.DocumentNavigationCache? = nil) -> PureXML.XPath.Node? {
        PureXML.XPath.AxisNavigation.firstByDocumentOrder(Array(self), cache: cache)
    }
}
