extension PureXML.XPath {
    /// A per-operation cache of each node's index among its parent's
    /// children. Document-order keys need the index at every ancestor level;
    /// without a cache each lookup scans the sibling list, so sorting a
    /// node-set drawn from one flat fan-out is quadratic (the 42 MB
    /// benchmark corpus spent 27 seconds there). Each distinct parent is
    /// enumerated exactly once.
    final class SiblingIndexCache {
        private var indexes: [ObjectIdentifier: [ObjectIdentifier: Int]] = [:]
        private var scannedOnce: Set<ObjectIdentifier> = []

        func index(of child: PureXML.Model.TreeNode, in parent: PureXML.Model.TreeNode) -> Int {
            let parentIdentity = ObjectIdentifier(parent)
            if let table = indexes[parentIdentity] {
                return table[ObjectIdentifier(child)] ?? 0
            }
            // The table only pays for itself from the second lookup under
            // the same parent: a single lookup (one key over a wide parent,
            // the per-predicate case that once built a million-entry table
            // per evaluation) scans linearly instead.
            guard scannedOnce.contains(parentIdentity) else {
                scannedOnce.insert(parentIdentity)
                return parent.children.firstIndex { $0 === child } ?? 0
            }
            var table: [ObjectIdentifier: Int] = [:]
            table.reserveCapacity(parent.children.count)
            for (index, node) in parent.children.enumerated() {
                table[ObjectIdentifier(node)] = index
            }
            indexes[parentIdentity] = table
            return table[ObjectIdentifier(child)] ?? 0
        }
    }
}
