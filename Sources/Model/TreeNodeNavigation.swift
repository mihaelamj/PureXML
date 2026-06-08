public extension PureXML.Model.TreeNode {
    /// The first child, or nil when there are none.
    var firstChild: PureXML.Model.TreeNode? {
        children.first
    }

    /// The last child, or nil when there are none.
    var lastChild: PureXML.Model.TreeNode? {
        children.last
    }

    /// The next sibling in document order, or nil when this is the last child or
    /// has no parent.
    var nextSibling: PureXML.Model.TreeNode? {
        guard let siblings = parent?.children, let index = indexInParent else { return nil }
        let next = index + 1
        return next < siblings.count ? siblings[next] : nil
    }

    /// The previous sibling in document order, or nil when this is the first child
    /// or has no parent.
    var previousSibling: PureXML.Model.TreeNode? {
        guard let siblings = parent?.children, let index = indexInParent, index > 0 else { return nil }
        return siblings[index - 1]
    }

    /// The element children only, skipping text, comments, and the rest.
    var elementChildren: [PureXML.Model.TreeNode] {
        children.filter { $0.kind == .element }
    }

    /// The chain of ancestors from the immediate parent up to the root.
    var ancestors: [PureXML.Model.TreeNode] {
        var result: [PureXML.Model.TreeNode] = []
        var current = parent
        while let node = current {
            result.append(node)
            current = node.parent
        }
        return result
    }

    /// The topmost ancestor (the node itself when it has no parent).
    var root: PureXML.Model.TreeNode {
        var current = self
        while let next = current.parent {
            current = next
        }
        return current
    }

    /// The concatenated text of every text and CDATA node in this subtree, in
    /// document order (the libxml2 `xmlNodeGetContent` behavior).
    var stringValue: String {
        switch kind {
        case .text, .cdata:
            value
        case .element, .document:
            children.reduce(into: "") { $0 += $1.stringValue }
        case .comment, .processingInstruction:
            ""
        }
    }

    /// This node's position among its parent's children, or nil when it has no
    /// parent.
    private var indexInParent: Int? {
        parent?.children.firstIndex { $0 === self }
    }
}
