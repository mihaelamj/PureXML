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

    /// The validation coding path from the document root to this node (a sibling
    /// index only when a name repeats), for locating schema compile findings.
    func validationCodingPath() -> [PureXML.Validation.PathKey] {
        var steps: [PureXML.Validation.PathKey] = []
        var current: PureXML.Model.TreeNode? = self
        while let element = current, element.kind == .element, let name = element.name?.description {
            steps.append(validationPathStep(for: element, named: name))
            current = element.parent
        }
        return steps.reversed()
    }

    private func validationPathStep(for element: PureXML.Model.TreeNode, named name: String) -> PureXML.Validation.PathKey {
        guard let parent = element.parent else { return .element(name) }
        let siblings = parent.children.filter { $0.kind == .element && $0.name?.description == name }
        guard siblings.count > 1, let index = siblings.firstIndex(where: { $0 === element }) else {
            return .element(name)
        }
        return .element(name, index: index + 1)
    }
}
