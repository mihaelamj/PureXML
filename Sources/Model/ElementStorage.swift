extension PureXML.Model {
    /// Copy-on-write backing for an ``Element``'s children.
    ///
    /// `Element` is a value type, but its children must live behind a reference so
    /// the tree's depth does not become part of any value's recursive layout: a
    /// chain of value-nested children would otherwise release one native frame per
    /// level and overflow the stack on a deeply-nested document. Holding children
    /// in this class gives the tree exactly one place to release them, where a
    /// custom `deinit` can flatten the subtree iteratively.
    ///
    /// `@unchecked Sendable`: the class is mutable, but ``Element`` only ever
    /// mutates `children` after copying a shared box (the copy-on-write check in
    /// `Element.children`'s setter), so a box reachable from more than one value is
    /// never written. That is the same discipline the standard library's own
    /// copy-on-write containers rely on to be `Sendable`.
    final class ElementStorage: @unchecked Sendable {
        var children: [PureXML.Model.Node]

        init(_ children: [PureXML.Model.Node]) {
            self.children = children
        }

        /// Releases the subtree without recursing on depth. A naive release walks
        /// one native frame per level (each box releasing its children's boxes);
        /// instead each uniquely-owned descendant's children are moved into a flat
        /// heap worklist and cleared before that node is released, so every box
        /// frees with empty children and the teardown stays flat. A node whose
        /// storage is still shared (a copy-on-write sibling holds it) is left
        /// intact and tears down later through this same `deinit`.
        deinit {
            guard !children.isEmpty else { return }
            var pending = children
            children = []
            while !pending.isEmpty {
                var node = pending.removeLast()
                node.drainUniquelyOwnedChildren(into: &pending)
            }
        }
    }
}
