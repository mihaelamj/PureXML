public extension PureXML.Model.TreeNode {
    /// Appends `child` as the last child, detaching it from any previous parent.
    func append(_ child: PureXML.Model.TreeNode) {
        insert(child, at: children.count)
    }

    /// Inserts `child` at `index` among the children (clamped to a valid range),
    /// detaching it from any previous parent first. Refuses to attach a node to
    /// itself or to one of its own descendants, which would form a cycle.
    func insert(_ child: PureXML.Model.TreeNode, at index: Int) {
        guard child !== self, !isDescendant(of: child) else { return }
        child.removeFromParent()
        let target = Swift.max(0, Swift.min(index, children.count))
        children.insert(child, at: target)
        child.parent = self
    }

    /// Inserts `child` immediately before `sibling` among this node's children.
    /// No-op if `sibling` is not a child of this node.
    func insert(_ child: PureXML.Model.TreeNode, before sibling: PureXML.Model.TreeNode) {
        guard let index = indexOfChild(sibling) else { return }
        insert(child, at: index)
    }

    /// Inserts `child` immediately after `sibling` among this node's children.
    /// No-op if `sibling` is not a child of this node.
    func insert(_ child: PureXML.Model.TreeNode, after sibling: PureXML.Model.TreeNode) {
        guard let index = indexOfChild(sibling) else { return }
        insert(child, at: index + 1)
    }

    /// Detaches this node from its parent, leaving it a standalone root.
    func removeFromParent() {
        guard let parent, let index = parent.indexOfChild(self) else { return }
        parent.children.remove(at: index)
        self.parent = nil
    }

    /// Removes `child` from this node's children. No-op if it is not a child.
    func removeChild(_ child: PureXML.Model.TreeNode) {
        guard child.parent === self else { return }
        child.removeFromParent()
    }

    /// Replaces this node in its parent with `replacement`, returning self
    /// detached. No-op (returns self) if this node has no parent.
    @discardableResult
    func replace(with replacement: PureXML.Model.TreeNode) -> PureXML.Model.TreeNode {
        guard let parent, let index = parent.indexOfChild(self) else { return self }
        parent.insert(replacement, at: index)
        removeFromParent()
        return self
    }

    /// Returns a deep copy of this subtree with no parent. Children are copied
    /// recursively; the copy shares no nodes with the original.
    func copy() -> PureXML.Model.TreeNode {
        let clone = PureXML.Model.TreeNode(
            kind: kind,
            name: name,
            attributes: attributes,
            value: value,
        )
        for child in children {
            clone.append(child.copy())
        }
        return clone
    }

    private func indexOfChild(_ child: PureXML.Model.TreeNode) -> Int? {
        children.firstIndex { $0 === child }
    }

    /// Whether this node is `ancestor` itself or appears below it.
    private func isDescendant(of ancestor: PureXML.Model.TreeNode) -> Bool {
        var current: PureXML.Model.TreeNode? = self
        while let node = current {
            if node === ancestor { return true }
            current = node.parent
        }
        return false
    }
}
