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

    /// The XPath string-value of this node. For an element, document, or root it
    /// is the concatenated text of the subtree (`textContent`); for a comment or
    /// processing instruction it is that node's own character data (XPath 1.0
    /// sections 5.6 and 5.7), which `value-of select="comment()"` returns.
    var stringValue: String {
        switch kind {
        case .text, .cdata, .namespace, .comment, .processingInstruction:
            value
        case .element, .document, .entityReference:
            textContent
        case .doctype:
            ""
        }
    }

    /// The concatenated text of every text and CDATA node in this subtree, in
    /// document order (the libxml2 `xmlNodeGetContent` behavior): an element's or
    /// root's string-value, where comment and processing-instruction descendants
    /// contribute nothing (XPath 1.0 sections 5.1 and 5.5). Distinct from
    /// `stringValue`, which on a comment or PI node is that node's own data.
    var textContent: String {
        switch kind {
        case .text, .cdata:
            value
        case .element, .document, .entityReference:
            children.reduce(into: "") { $0 += $1.textContent }
        case .namespace, .comment, .processingInstruction, .doctype:
            ""
        }
    }

    /// This node's position among its parent's children, or nil when it has no
    /// parent.
    private var indexInParent: Int? {
        parent?.children.firstIndex { $0 === self }
    }
}
