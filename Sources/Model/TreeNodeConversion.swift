public extension PureXML.Model.TreeNode {
    /// Builds a mutable tree from a parsed value ``Node``, wiring up parent links.
    convenience init(_ node: PureXML.Model.Node) {
        switch node {
        case let .document(children):
            self.init(kind: .document, children: children.map(PureXML.Model.TreeNode.init))
        case let .element(element):
            self.init(
                kind: .element,
                name: element.name,
                attributes: element.attributes,
                children: element.children.map(PureXML.Model.TreeNode.init),
            )
        case let .text(value):
            self.init(kind: .text, value: value)
        case let .cdata(value):
            self.init(kind: .cdata, value: value)
        case let .comment(value):
            self.init(kind: .comment, value: value)
        case let .processingInstruction(target, data):
            self.init(kind: .processingInstruction, name: PureXML.Model.QualifiedName(target), value: data)
        }
    }

    /// Rebuilds an immutable value ``Node`` from this subtree, for serialization
    /// or value comparison.
    var node: PureXML.Model.Node {
        switch kind {
        case .document:
            .document(children.map(\.node))
        case .element:
            .element(PureXML.Model.Element(
                name: name ?? PureXML.Model.QualifiedName(""),
                attributes: attributes,
                children: children.map(\.node),
            ))
        case .text:
            .text(value)
        case .cdata:
            .cdata(value)
        case .comment:
            .comment(value)
        case .processingInstruction:
            .processingInstruction(target: name?.description ?? "", data: value)
        }
    }
}
