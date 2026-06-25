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
        private var attributeIndexes: [ObjectIdentifier: [PureXML.Model.QualifiedName: Int]] = [:]
        private var attributeScannedOnce: Set<ObjectIdentifier> = []

        /// The index of an attribute, by name, among its owner's attributes, for
        /// the attribute band of a document-order key. As with ``index(of:in:)``,
        /// the per-owner table is built on the second lookup (a single lookup
        /// scans), so sorting many attribute nodes from one element is linear
        /// rather than quadratic in the attribute count.
        func attributeIndex(of name: PureXML.Model.QualifiedName, in owner: PureXML.Model.TreeNode) -> Int {
            let ownerIdentity = ObjectIdentifier(owner)
            if let table = attributeIndexes[ownerIdentity] {
                return table[name] ?? 0
            }
            guard attributeScannedOnce.contains(ownerIdentity) else {
                attributeScannedOnce.insert(ownerIdentity)
                return owner.attributes.firstIndex { $0.name == name } ?? 0
            }
            var table: [PureXML.Model.QualifiedName: Int] = [:]
            table.reserveCapacity(owner.attributes.count)
            for (index, attribute) in owner.attributes.enumerated() where table[attribute.name] == nil {
                table[attribute.name] = index
            }
            attributeIndexes[ownerIdentity] = table
            return table[name] ?? 0
        }

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
