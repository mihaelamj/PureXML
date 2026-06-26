public extension PureXML.Model.TreeNode {
    /// Builds a mutable tree from a parsed value ``Node``, wiring up parent links.
    ///
    /// The conversion is iterative, not recursive on depth: a deeply-nested
    /// document is built bottom-up through an explicit work stack so construction
    /// stays in bounded native stack (see ``buildForest(_:)``).
    convenience init(_ node: PureXML.Model.Node) {
        switch node {
        case let .document(children):
            self.init(adopting: .document, children: Self.buildForest(children))
        case let .element(element):
            self.init(
                adopting: .element,
                name: element.name,
                attributes: element.attributes,
                children: Self.buildForest(element.children),
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

    /// Builds the `TreeNode` children for a forest of value ``Node``s without
    /// recursing on tree depth. A frame holds a branch node (element or document)
    /// being converted: the position of the next source child to process and the
    /// `TreeNode` children built so far. Leaves convert directly; a branch is
    /// assembled (adopting its built children, which sets their parent links) only
    /// once all its source children are done, then handed to its own parent frame.
    /// A synthetic document frame carries the roots; it is never assembled (that
    /// would re-parent them), so its built children are the result.
    private static func buildForest(_ roots: [PureXML.Model.Node]) -> [PureXML.Model.TreeNode] {
        let rootFrame = BuildFrame(.document(roots), roots)
        var stack: [BuildFrame] = [rootFrame]
        while let frame = stack.last {
            guard frame.next < frame.children.count else {
                stack.removeLast()
                guard let parent = stack.last else { break }
                parent.built.append(buildBranch(frame))
                continue
            }
            let child = frame.children[frame.next]
            frame.next += 1
            if let grandchildren = branchChildren(child) {
                stack.append(BuildFrame(child, grandchildren))
            } else {
                frame.built.append(buildLeaf(child))
            }
        }
        return rootFrame.built
    }

    /// Rebuilds an immutable value ``Node`` from this subtree, for serialization
    /// or value comparison. Iterative on depth (see ``projectedChildren(of:)``).
    var node: PureXML.Model.Node {
        switch kind {
        case .document:
            .document(Self.projectedChildren(of: self))
        case .element:
            .element(PureXML.Model.Element(
                name: name ?? PureXML.Model.QualifiedName(""),
                attributes: attributes,
                children: Self.projectedChildren(of: self),
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

    /// The value-`Node` children of `root`'s subtree, projected into a pure
    /// content tree without recursing on depth: doctype and namespace nodes are
    /// dropped (they carry no content), and an entity-reference node is spliced
    /// open into its replacement nodes. A frame accumulates a branch node's
    /// projected children; on completion an element or document frame wraps them
    /// in the corresponding value `Node`, while an entity-reference frame splices
    /// them into its parent (no wrapper).
    private static func projectedChildren(of root: PureXML.Model.TreeNode) -> [PureXML.Model.Node] {
        let rootFrame = ProjectFrame(root, splice: false)
        var stack: [ProjectFrame] = [rootFrame]
        while let frame = stack.last {
            guard frame.next < frame.tree.children.count else {
                stack.removeLast()
                guard let parent = stack.last else { break }
                finishProjection(frame, into: parent)
                continue
            }
            let child = frame.tree.children[frame.next]
            frame.next += 1
            switch child.kind {
            case .doctype, .namespace:
                continue
            case .entityReference:
                stack.append(ProjectFrame(child, splice: true))
            case .element, .document:
                stack.append(ProjectFrame(child, splice: false))
            default:
                frame.built.append(projectLeaf(child))
            }
        }
        return rootFrame.built
    }

    // MARK: Build helpers

    private static func branchChildren(_ node: PureXML.Model.Node) -> [PureXML.Model.Node]? {
        switch node {
        case let .document(children): children
        case let .element(element): element.children
        default: nil
        }
    }

    private static func buildLeaf(_ node: PureXML.Model.Node) -> PureXML.Model.TreeNode {
        switch node {
        case let .text(value): PureXML.Model.TreeNode(kind: .text, value: value)
        case let .cdata(value): PureXML.Model.TreeNode(kind: .cdata, value: value)
        case let .comment(value): PureXML.Model.TreeNode(kind: .comment, value: value)
        case let .processingInstruction(target, data):
            PureXML.Model.TreeNode(kind: .processingInstruction, name: PureXML.Model.QualifiedName(target), value: data)
        // Unreachable: `buildLeaf` is only called when `branchChildren` returned
        // nil (a non-branch node). An empty text node keeps the conversion total.
        case .document, .element: PureXML.Model.TreeNode(kind: .text, value: "")
        }
    }

    private static func buildBranch(_ frame: BuildFrame) -> PureXML.Model.TreeNode {
        switch frame.node {
        case let .element(element):
            PureXML.Model.TreeNode(adopting: .element, name: element.name, attributes: element.attributes, children: frame.built)
        // Only branch nodes (document or element) get a frame; a non-branch frame
        // is unreachable, so the document shape is a total fallback.
        default:
            PureXML.Model.TreeNode(adopting: .document, children: frame.built)
        }
    }

    // MARK: Projection helpers

    private static func projectLeaf(_ tree: PureXML.Model.TreeNode) -> PureXML.Model.Node {
        switch tree.kind {
        case .cdata: .cdata(tree.value)
        case .comment: .comment(tree.value)
        case .processingInstruction:
            .processingInstruction(target: tree.name?.description ?? "", data: tree.value)
        // doctype/namespace are dropped before reaching here; everything else
        // projects as the text leaf.
        default: .text(tree.value)
        }
    }

    /// Resolves a completed frame into `parent`'s children: an entity-reference
    /// frame splices its projected nodes in, an element wraps them, and any other
    /// branch (a document) wraps them as a document.
    private static func finishProjection(_ frame: ProjectFrame, into parent: ProjectFrame) {
        if frame.splice {
            parent.built.append(contentsOf: frame.built)
        } else if case .element = frame.tree.kind {
            parent.built.append(.element(PureXML.Model.Element(
                name: frame.tree.name ?? PureXML.Model.QualifiedName(""),
                attributes: frame.tree.attributes,
                children: frame.built,
            )))
        } else {
            parent.built.append(.document(frame.built))
        }
    }

    /// Like ``node`` but reuses subtrees already projected during this pass through
    /// `memo` (keyed by tree-node identity). Projecting several result nodes that
    /// nest within one another then shares structure (copy-on-write) instead of
    /// rebuilding each subtree, so a result set of nested nodes is linear rather
    /// than quadratic. The projection is identical to ``node``.
    func node(memo: inout [ObjectIdentifier: PureXML.Model.Node]) -> PureXML.Model.Node {
        if let cached = memo[ObjectIdentifier(self)] { return cached }
        let result: PureXML.Model.Node = switch kind {
        case .document:
            .document(Self.projectedChildren(of: self, memo: &memo))
        case .element:
            .element(PureXML.Model.Element(
                name: name ?? PureXML.Model.QualifiedName(""),
                attributes: attributes,
                children: Self.projectedChildren(of: self, memo: &memo),
            ))
        case .text: .text(value)
        case .entityReference: .text(stringValue)
        case .cdata: .cdata(value)
        case .comment: .comment(value)
        case .processingInstruction: .processingInstruction(target: name?.description ?? "", data: value)
        case .doctype, .namespace: .text("")
        }
        memo[ObjectIdentifier(self)] = result
        return result
    }

    /// ``projectedChildren(of:)`` that caches each element/document subtree in
    /// `memo` and reuses an already-projected child instead of walking it again.
    private static func projectedChildren(of root: PureXML.Model.TreeNode, memo: inout [ObjectIdentifier: PureXML.Model.Node]) -> [PureXML.Model.Node] {
        let rootFrame = ProjectFrame(root, splice: false)
        var stack: [ProjectFrame] = [rootFrame]
        while let frame = stack.last {
            guard frame.next < frame.tree.children.count else {
                stack.removeLast()
                guard let parent = stack.last else { break }
                finishProjection(frame, into: parent, memo: &memo)
                continue
            }
            let child = frame.tree.children[frame.next]
            frame.next += 1
            switch child.kind {
            case .doctype, .namespace:
                continue
            case .entityReference:
                stack.append(ProjectFrame(child, splice: true))
            case .element, .document:
                if let cached = memo[ObjectIdentifier(child)] {
                    frame.built.append(cached)
                } else {
                    stack.append(ProjectFrame(child, splice: false))
                }
            default:
                frame.built.append(projectLeaf(child))
            }
        }
        return rootFrame.built
    }

    /// ``finishProjection(_:into:)`` that also records an element or document
    /// frame's projected node in `memo` for reuse.
    private static func finishProjection(_ frame: ProjectFrame, into parent: ProjectFrame, memo: inout [ObjectIdentifier: PureXML.Model.Node]) {
        if frame.splice {
            parent.built.append(contentsOf: frame.built)
            return
        }
        let node: PureXML.Model.Node = if case .element = frame.tree.kind {
            .element(PureXML.Model.Element(
                name: frame.tree.name ?? PureXML.Model.QualifiedName(""),
                attributes: frame.tree.attributes,
                children: frame.built,
            ))
        } else {
            .document(frame.built)
        }
        memo[ObjectIdentifier(frame.tree)] = node
        parent.built.append(node)
    }
}

/// A branch node being converted from a value ``Node`` to a ``TreeNode``: the
/// source children, the cursor into them, and the converted children so far.
private final class BuildFrame {
    let node: PureXML.Model.Node
    let children: [PureXML.Model.Node]
    var next = 0
    var built: [PureXML.Model.TreeNode] = []
    init(_ node: PureXML.Model.Node, _ children: [PureXML.Model.Node]) {
        self.node = node
        self.children = children
    }
}

/// A ``TreeNode`` being projected back to a value ``Node``: `splice` marks an
/// entity-reference frame whose projected children fold into its parent.
private final class ProjectFrame {
    let tree: PureXML.Model.TreeNode
    let splice: Bool
    var next = 0
    var built: [PureXML.Model.Node] = []
    init(_ tree: PureXML.Model.TreeNode, splice: Bool) {
        self.tree = tree
        self.splice = splice
    }
}
