/// A partially-built ``TreeNode`` element while its children stream in, the
/// direct-tree counterpart to `ElementFrame`. File-scope and private.
private struct TreeNodeFrame {
    let name: PureXML.Model.QualifiedName
    let attributes: [PureXML.Model.Attribute]
    var children: [PureXML.Model.TreeNode] = []
}

public extension PureXML.Parsing.Parser {
    /// Parses a string straight into the mutable, parent-aware ``TreeNode`` tree,
    /// assembling it directly from the event stream instead of building the value
    /// ``Node`` tree and converting it. The result is identical to
    /// ``Model/TreeNode/init(_:)`` applied to ``parse(_:limits:resolver:)``, the
    /// same nodes with the same parent links, but the tree is allocated once
    /// rather than twice.
    func parseTree(
        _ xml: String,
        limits: PureXML.Parsing.Limits = .default,
        resolver: PureXML.Parsing.EntityResolver = .refusing,
    ) throws -> PureXML.Model.TreeNode {
        try buildTree(PureXML.Parsing.EventReader(xml, limits: limits, resolver: resolver))
    }

    /// The direct-``TreeNode`` counterpart to `build(_:)`: same event loop, same
    /// stack discipline, same well-formedness guards, but it accumulates
    /// ``TreeNode`` children per frame and adopts them when an element closes, so
    /// it never materializes the intermediate value ``Node`` tree. Each produced
    /// tree is identical to converting `build(_:)`'s node.
    internal func buildTree(_ source: PureXML.Parsing.EventReader) throws -> PureXML.Model.TreeNode {
        var reader = source
        var roots: [PureXML.Model.TreeNode] = []
        var stack: [TreeNodeFrame] = []
        var produced = false

        while let event = try reader.next() {
            produced = true
            switch event {
            case let .startElement(name, attributes):
                stack.append(TreeNodeFrame(name: name, attributes: attributes))
            case .endElement:
                guard let frame = stack.popLast() else {
                    throw PureXML.Parsing.ParseError.unexpectedEndOfInput(.start)
                }
                let element = PureXML.Model.TreeNode(
                    adopting: .element,
                    name: frame.name,
                    attributes: frame.attributes,
                    children: frame.children,
                )
                attachTree(element, to: &stack, roots: &roots)
            case let .characters(text):
                attachTree(PureXML.Model.TreeNode(kind: .text, value: text), to: &stack, roots: &roots)
            case let .cdata(text):
                attachTree(PureXML.Model.TreeNode(kind: .cdata, value: text), to: &stack, roots: &roots)
            case let .comment(text):
                attachTree(PureXML.Model.TreeNode(kind: .comment, value: text), to: &stack, roots: &roots)
            case let .processingInstruction(target, data):
                let instruction = PureXML.Model.TreeNode(
                    kind: .processingInstruction,
                    name: PureXML.Model.QualifiedName(target),
                    value: data,
                )
                attachTree(instruction, to: &stack, roots: &roots)
            }
        }

        guard produced, roots.contains(where: { $0.kind == .element }) else {
            throw PureXML.Parsing.ParseError.emptyDocument
        }
        return PureXML.Model.TreeNode(adopting: .document, children: roots)
    }

    private func attachTree(
        _ node: PureXML.Model.TreeNode,
        to stack: inout [TreeNodeFrame],
        roots: inout [PureXML.Model.TreeNode],
    ) {
        if stack.isEmpty {
            roots.append(node)
        } else {
            stack[stack.count - 1].children.append(node)
        }
    }
}
