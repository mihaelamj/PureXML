public extension PureXML.Model.TreeNode {
    /// Resolves a validation coding path to the node it addresses, navigating from
    /// this node (typically the document) down by element name, using a sibling
    /// index only when a name repeats. The same convention the validators build
    /// paths with, so a ``PureXML/Validation/ValidationError``'s `codingPath` maps
    /// to a node here, and the node's `sourceRange` gives the span to highlight.
    /// An attribute step (`@name`) resolves to its owning element.
    func node(at path: [PureXML.Validation.PathKey]) -> PureXML.Model.TreeNode? {
        var current: PureXML.Model.TreeNode? = self
        for key in path {
            guard let node = current else { return nil }
            if key.stringValue.hasPrefix("@") { return node }
            let matches = node.children.filter { $0.kind == .element && $0.name?.description == key.stringValue }
            let index = (key.intValue ?? 1) - 1
            current = matches.indices.contains(index) ? matches[index] : nil
        }
        return current
    }

    /// The source span of the node a validation coding path addresses, when known.
    func sourceRange(at path: [PureXML.Validation.PathKey]) -> PureXML.Parsing.SourceRange? {
        node(at: path)?.sourceRange
    }
}
