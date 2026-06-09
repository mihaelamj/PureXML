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
            .document(projectedChildren)
        case .element:
            .element(PureXML.Model.Element(
                name: name ?? PureXML.Model.QualifiedName(""),
                attributes: attributes,
                children: projectedChildren,
            ))
        case .text:
            .text(value)
        case .entityReference:
            .text(stringValue)
        case .cdata:
            .cdata(value)
        case .comment:
            .comment(value)
        case .processingInstruction:
            .processingInstruction(target: name?.description ?? "", data: value)
        case .doctype, .namespace:
            // DOM-structural kinds with no place in the content value model; they
            // are dropped from a parent's projection (see projectedChildren), so a
            // direct call here yields empty text only as a defensive fallback.
            .text("")
        }
    }

    /// The value-`Node` children of this subtree: doctype and namespace nodes are
    /// dropped (they carry no content), and an entity-reference node is spliced
    /// open into its replacement nodes, so the projection is a pure content tree.
    private var projectedChildren: [PureXML.Model.Node] {
        children.flatMap { child -> [PureXML.Model.Node] in
            switch child.kind {
            case .doctype, .namespace:
                []
            case .entityReference:
                child.projectedChildren
            default:
                [child.node]
            }
        }
    }
}
