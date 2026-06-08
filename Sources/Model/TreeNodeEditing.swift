public extension PureXML.Model.TreeNode {
    // MARK: Attribute helpers

    /// The value of the attribute named `name` (by `prefix:local` rendering or by
    /// local name), or nil when the element has no such attribute.
    func attributeValue(_ name: String) -> String? {
        attributes.first { $0.name.description == name || $0.name.localName == name }?.value
    }

    /// Sets the attribute named `name` to `value`, updating it in place when it is
    /// already present (matched by `prefix:local` rendering) or appending it
    /// otherwise. A no-op on a non-element node.
    func setAttribute(_ name: String, _ value: String) {
        guard kind == .element else { return }
        if let index = attributes.firstIndex(where: { $0.name.description == name }) {
            attributes[index].value = value
        } else {
            attributes.append(PureXML.Model.Attribute(name, value))
        }
    }

    /// Removes the attribute named `name` (by `prefix:local` rendering or local
    /// name), returning whether one was removed.
    @discardableResult
    func removeAttribute(_ name: String) -> Bool {
        guard let index = attributes.firstIndex(where: { $0.name.description == name || $0.name.localName == name }) else {
            return false
        }
        attributes.remove(at: index)
        return true
    }

    // MARK: Copying

    /// Returns a copy of this node alone, with no children and no parent. The
    /// element's name, attributes, and value are carried over. Complements the
    /// deep ``copy()``.
    func shallowCopy() -> PureXML.Model.TreeNode {
        PureXML.Model.TreeNode(kind: kind, name: name, attributes: attributes, value: value)
    }

    // MARK: Document order

    /// Whether this node strictly precedes `other` in document order. Two nodes are
    /// comparable only when they share a root; an unrelated node returns false. An
    /// ancestor precedes its descendants.
    func precedes(_ other: PureXML.Model.TreeNode) -> Bool {
        if self === other { return false }
        let mine = Self.pathFromRoot(self)
        let theirs = Self.pathFromRoot(other)
        guard mine.first === theirs.first else { return false }
        var depth = 0
        while depth < mine.count, depth < theirs.count, mine[depth] === theirs[depth] {
            depth += 1
        }
        if depth == mine.count { return true }
        if depth == theirs.count { return false }
        let parent = mine[depth - 1]
        let mineIndex = parent.children.firstIndex { $0 === mine[depth] } ?? 0
        let theirsIndex = parent.children.firstIndex { $0 === theirs[depth] } ?? 0
        return mineIndex < theirsIndex
    }

    private static func pathFromRoot(_ node: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
        var path = [node]
        var current = node
        while let parent = current.parent {
            path.append(parent)
            current = parent
        }
        return path.reversed()
    }

    // MARK: Normalization

    /// Coalesces adjacent text children into one, drops empty text children, and
    /// normalizes each element child recursively (the DOM `normalize` behavior).
    /// CDATA sections are left intact and never merged with text.
    func normalize() {
        var result: [PureXML.Model.TreeNode] = []
        for child in children {
            if child.kind == .text {
                if child.value.isEmpty {
                    child.parent = nil
                    continue
                }
                if let last = result.last, last.kind == .text {
                    last.value += child.value
                    child.parent = nil
                    continue
                }
            } else {
                child.normalize()
            }
            result.append(child)
        }
        children = result
    }
}
