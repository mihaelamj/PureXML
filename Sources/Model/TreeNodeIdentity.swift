public extension PureXML.Model.TreeNode {
    /// The document node this node ultimately lives under, or nil when the node
    /// is detached or rooted at something other than a document (the DOM
    /// `ownerDocument`). Derived from the parent chain, so it stays correct after
    /// any move or adoption without a separate identity field.
    var ownerDocument: PureXML.Model.TreeNode? {
        let top = root
        return top.kind == .document ? top : nil
    }

    /// Detaches `node` from its current tree and makes it self-contained for this
    /// document (the DOM `adoptNode`): every namespace the subtree relied on from
    /// an outer scope is re-declared on the subtree, so moving it never silently
    /// rebinds a prefix. Returns the adopted node, ready to insert with
    /// ``append(_:)`` or one of the `insert` methods.
    @discardableResult
    func adopt(_ node: PureXML.Model.TreeNode) -> PureXML.Model.TreeNode {
        Self.rebindNamespaces(on: node)
        node.removeFromParent()
        return node
    }

    /// A self-contained copy of `node` for use in this document (the DOM
    /// `importNode`), leaving the original where it is. Deep by default; pass
    /// `deep: false` for a shallow copy. Namespaces the subtree relied on from an
    /// outer scope are re-declared on the copy so it carries its own bindings.
    func importNode(_ node: PureXML.Model.TreeNode, deep: Bool = true) -> PureXML.Model.TreeNode {
        let copy = deep ? node.copy() : node.shallowCopy()
        Self.rebindNamespaces(on: copy)
        return copy
    }

    // MARK: Typed accessors for the structural node kinds

    /// The document-type (root element) name of a `.doctype` node.
    var doctypeName: String? {
        kind == .doctype ? name?.description : nil
    }

    /// The public identifier of a `.doctype` node, when it has an external subset.
    var publicID: String? {
        kind == .doctype ? attributeValue("public") : nil
    }

    /// The system identifier of a `.doctype` node, when it has an external subset.
    var systemID: String? {
        kind == .doctype ? attributeValue("system") : nil
    }

    /// The internal subset text of a `.doctype` node (empty when it has none).
    var internalSubset: String? {
        kind == .doctype ? value : nil
    }

    /// The entity name of a `.entityReference` node (without the `&` and `;`).
    var entityReferenceName: String? {
        kind == .entityReference ? name?.description : nil
    }

    /// The prefix bound by a `.namespace` node, or nil for the default namespace.
    var namespacePrefix: String? {
        guard kind == .namespace, let local = name?.localName, !local.isEmpty else { return nil }
        return local
    }

    /// The URI bound by a `.namespace` node.
    var namespaceBinding: String? {
        kind == .namespace ? value : nil
    }

    /// Re-declares on `root` every namespace its subtree uses, so a moved or
    /// copied subtree no longer depends on declarations that lived on outer
    /// ancestors. Only adds a declaration the node does not already carry, so an
    /// inner rebinding (which travels as its own `xmlns` attribute) is preserved.
    private static func rebindNamespaces(on root: PureXML.Model.TreeNode) {
        guard root.kind == .element else { return }
        var declared = Set(root.attributes.map(\.name.description))
        for (attributeName, uri) in usedNamespaces(in: root) where !declared.contains(attributeName) {
            root.attributes.append(PureXML.Model.Attribute(attributeName, uri))
            declared.insert(attributeName)
        }
    }

    /// The `xmlns`/`xmlns:prefix` declarations the subtree's resolved names imply,
    /// keyed by the declaration's attribute name. An element contributes its own
    /// namespace; a prefixed attribute contributes its prefix's namespace.
    private static func usedNamespaces(in node: PureXML.Model.TreeNode) -> [String: String] {
        var result: [String: String] = [:]
        var stack = [node]
        while let current = stack.popLast() {
            if current.kind == .element, let uri = current.name?.namespaceURI {
                result[declarationName(forPrefix: current.name?.prefix)] = uri
            }
            for attribute in current.attributes {
                if let prefix = attribute.name.prefix, prefix != "xmlns", let uri = attribute.name.namespaceURI {
                    result["xmlns:\(prefix)"] = uri
                }
            }
            stack.append(contentsOf: current.children)
        }
        return result
    }

    private static func declarationName(forPrefix prefix: String?) -> String {
        guard let prefix, !prefix.isEmpty else { return "xmlns" }
        return "xmlns:\(prefix)"
    }
}
