extension PureXML.Model.Node {
    /// Rebuilds this tree bottom-up without recursing on the tree's depth, so a
    /// transform over a deeply-nested document cannot overflow the stack. Each
    /// node is passed to `transform` once its children have been rebuilt, together
    /// with those rebuilt children (empty for a leaf); the transform returns the
    /// replacement node. An explicit work stack drives a post-order walk, so a
    /// parent is transformed only after all its descendants.
    ///
    /// This is the shared spine for the tree-to-tree transforms (DTD default
    /// application, canonical prefix rewriting, and the like) that previously
    /// recursed one native frame per level.
    func rebuildingBottomUp(
        _ transform: (_ node: PureXML.Model.Node, _ rebuiltChildren: [PureXML.Model.Node]) -> PureXML.Model.Node,
    ) -> PureXML.Model.Node {
        guard let rootChildren = Self.branchChildren(self) else {
            return transform(self, [])
        }
        let rootFrame = RebuildFrame(self, rootChildren)
        var stack: [RebuildFrame] = [rootFrame]
        while let frame = stack.last {
            guard frame.next < frame.children.count else {
                stack.removeLast()
                let rebuilt = transform(frame.node, frame.built)
                if let parent = stack.last {
                    parent.built.append(rebuilt)
                } else {
                    return rebuilt
                }
                continue
            }
            let child = frame.children[frame.next]
            frame.next += 1
            if let grandchildren = Self.branchChildren(child) {
                stack.append(RebuildFrame(child, grandchildren))
            } else {
                frame.built.append(transform(child, []))
            }
        }
        return transform(self, [])
    }

    /// The children of a branch node (document or element), or nil for a leaf.
    private static func branchChildren(_ node: PureXML.Model.Node) -> [PureXML.Model.Node]? {
        switch node {
        case let .document(children): children
        case let .element(element): element.children
        default: nil
        }
    }
}

/// A node being rebuilt bottom-up: its source children, the cursor into them, and
/// the rebuilt children gathered so far.
private final class RebuildFrame {
    let node: PureXML.Model.Node
    let children: [PureXML.Model.Node]
    var next = 0
    var built: [PureXML.Model.Node] = []

    init(_ node: PureXML.Model.Node, _ children: [PureXML.Model.Node]) {
        self.node = node
        self.children = children
    }
}
