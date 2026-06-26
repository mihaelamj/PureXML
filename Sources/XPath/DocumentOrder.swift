extension PureXML.XPath.AxisNavigation {
    /// A document-order sort key. Comparing two nodes is O(1): the document each
    /// belongs to (ranked by first appearance), the pre-order index of the node's
    /// owning tree node, a band placing an element before its namespace nodes
    /// before its attribute nodes before its children, and a tie-breaking
    /// sub-index. This replaces the former per-node root path, an array as long as
    /// the node's depth, which made ordering a deep document quadratic.
    private struct OrderKey: Comparable {
        var rootRank = 0
        var index = 0
        var band = 0
        var sub = 0

        static func < (lhs: OrderKey, rhs: OrderKey) -> Bool {
            if lhs.rootRank != rhs.rootRank { return lhs.rootRank < rhs.rootRank }
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            if lhs.band != rhs.band { return lhs.band < rhs.band }
            return lhs.sub < rhs.sub
        }
    }

    /// Sorts `nodes` into XPath document order using a per-root pre-order index
    /// (built once and cached) rather than a per-node root path, so the sort is
    /// O(n log n + document) instead of O(n log n x depth).
    ///
    /// A node-set spanning several documents (an XSLT `document()` result) is
    /// grouped by root, ranked by first appearance; only a node outside the first
    /// node's document pays an O(depth) root walk, so the common single-document
    /// case never walks a node's ancestors.
    static func sortByDocumentOrder(_ nodes: [PureXML.XPath.Node], cache: PureXML.XPath.DocumentNavigationCache?) -> [PureXML.XPath.Node] {
        guard nodes.count > 1, let primaryRoot = rootTree(of: nodes[0]) else { return nodes }
        return decorate(nodes, primaryRoot: primaryRoot, cache: cache)
            .sorted { $0.key < $1.key }
            .map(\.node)
    }

    /// The single node first in document order, by the same keying as
    /// ``sortByDocumentOrder(_:cache:)`` but in O(n) rather than a full sort.
    static func firstByDocumentOrder(_ nodes: [PureXML.XPath.Node], cache: PureXML.XPath.DocumentNavigationCache?) -> PureXML.XPath.Node? {
        guard nodes.count > 1, let primaryRoot = rootTree(of: nodes[0]) else { return nodes.first }
        return decorate(nodes, primaryRoot: primaryRoot, cache: cache)
            .min { $0.key < $1.key }?
            .node
    }

    /// Pairs each node with its document-order key. The primary document's index
    /// is built once; a foreign node falls back to its own document's index,
    /// ranked after the primary by first appearance.
    private static func decorate(
        _ nodes: [PureXML.XPath.Node],
        primaryRoot: PureXML.Model.TreeNode,
        cache: PureXML.XPath.DocumentNavigationCache?,
    ) -> [(node: PureXML.XPath.Node, key: OrderKey)] {
        let primaryID = ObjectIdentifier(primaryRoot)
        var indexByRoot: [ObjectIdentifier: [PureXML.XPath.Node: Int]] = [primaryID: orderedDocument(rootedAt: primaryRoot, cache: cache).index]
        var rootRank: [ObjectIdentifier: Int] = [primaryID: 0]
        return nodes.map { node in
            if var key = compactKey(node, in: indexByRoot[primaryID] ?? [:]) {
                key.rootRank = 0
                return (node, key)
            }
            guard let root = rootTree(of: node) else { return (node, OrderKey(rootRank: .max)) }
            let rootID = ObjectIdentifier(root)
            let rank: Int
            if let existing = rootRank[rootID] {
                rank = existing
            } else {
                rank = rootRank.count
                rootRank[rootID] = rank
                indexByRoot[rootID] = orderedDocument(rootedAt: root, cache: cache).index
            }
            var key = compactKey(node, in: indexByRoot[rootID] ?? [:]) ?? OrderKey()
            key.rootRank = rank
            return (node, key)
        }
    }

    /// `node`'s order key within `index` (a pre-order numbering of one document's
    /// tree nodes), or nil when `node` belongs to a different document. The band
    /// orders an element before its namespace nodes before its attribute nodes
    /// before its children (whose own index is greater), mirroring the bands of
    /// the former path-key form.
    private static func compactKey(_ node: PureXML.XPath.Node, in index: [PureXML.XPath.Node: Int]) -> OrderKey? {
        switch node {
        case .tree:
            guard let position = index[node] else { return nil }
            return OrderKey(index: position, band: 0)
        case let .attribute(owner, attribute):
            guard let position = index[.tree(owner)] else { return nil }
            let attributeIndex = owner.attributes.firstIndex { $0.name == attribute.name } ?? 0
            return OrderKey(index: position, band: 2, sub: attributeIndex)
        case let .namespace(owner, prefix, _):
            guard let position = index[.tree(owner)] else { return nil }
            return OrderKey(index: position, band: 1, sub: prefix.hashValue)
        }
    }
}
