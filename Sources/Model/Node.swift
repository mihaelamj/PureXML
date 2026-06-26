public extension PureXML.Model {
    /// A node in an XML tree. The model preserves document order and the
    /// distinction between text, CDATA, comments, and processing instructions
    /// so that emitting can round-trip a parsed document.
    ///
    /// Not `indirect`: an element holds its children behind a reference
    /// (``ElementStorage``), so a `Node` is a fixed-size value and the tree's
    /// depth is not part of any value's layout. Equality, hashing, and release
    /// all walk the tree iteratively, so an arbitrarily deep document never
    /// overflows the call stack.
    enum Node: Sendable {
        /// The root of a parsed document, holding its prolog and root element.
        case document([Node])
        /// An element with a name, attributes, and children.
        case element(Element)
        /// Character data between markup.
        case text(String)
        /// A `<![CDATA[ ... ]]>` section. Stored as its raw inner text.
        case cdata(String)
        /// A `<!-- ... -->` comment. Stored as its raw inner text.
        case comment(String)
        /// A `<?target data?>` processing instruction.
        case processingInstruction(target: String, data: String)

        /// The wrapped ``Element`` when this node is an element.
        public var element: Element? {
            guard case let .element(element) = self else { return nil }
            return element
        }
    }
}

extension PureXML.Model.Node: Equatable, Hashable {
    public static func == (lhs: Self, rhs: Self) -> Bool {
        treesEqual(lhs, rhs)
    }

    /// Whether two node trees are equal, compared iteratively through an explicit
    /// pair stack so a deeply-nested tree does not recurse one frame per level.
    static func treesEqual(_ lhs: Self, _ rhs: Self) -> Bool {
        var stack: [(Self, Self)] = [(lhs, rhs)]
        while let (left, right) = stack.popLast() {
            switch (left, right) {
            case let (.element(leftElement), .element(rightElement)):
                guard leftElement.name == rightElement.name,
                      leftElement.attributes == rightElement.attributes,
                      leftElement.children.count == rightElement.children.count
                else { return false }
                for pair in zip(leftElement.children, rightElement.children) {
                    stack.append(pair)
                }
            case let (.document(leftChildren), .document(rightChildren)):
                guard leftChildren.count == rightChildren.count else { return false }
                for pair in zip(leftChildren, rightChildren) {
                    stack.append(pair)
                }
            default:
                if !leavesEqual(left, right) { return false }
            }
        }
        return true
    }

    /// Equality for the non-branch node kinds (and a kind mismatch); the branch
    /// kinds are walked iteratively by ``treesEqual(_:_:)``.
    private static func leavesEqual(_ left: Self, _ right: Self) -> Bool {
        switch (left, right) {
        case let (.text(leftValue), .text(rightValue)): leftValue == rightValue
        case let (.cdata(leftValue), .cdata(rightValue)): leftValue == rightValue
        case let (.comment(leftValue), .comment(rightValue)): leftValue == rightValue
        case let (.processingInstruction(leftTarget, leftData), .processingInstruction(rightTarget, rightData)):
            leftTarget == rightTarget && leftData == rightData
        default: false
        }
    }

    /// Hashes the whole subtree iteratively (pre-order), consistent with
    /// ``treesEqual(_:_:)``: equal trees feed the hasher the same sequence.
    public func hash(into hasher: inout Hasher) {
        var stack: [Self] = [self]
        while let node = stack.popLast() {
            switch node {
            case let .element(element):
                hasher.combine(0)
                hasher.combine(element.name)
                hasher.combine(element.attributes)
                hasher.combine(element.children.count)
                for child in element.children {
                    stack.append(child)
                }
            case let .document(children):
                hasher.combine(1)
                hasher.combine(children.count)
                for child in children {
                    stack.append(child)
                }
            case let .text(value):
                hasher.combine(2)
                hasher.combine(value)
            case let .cdata(value):
                hasher.combine(3)
                hasher.combine(value)
            case let .comment(value):
                hasher.combine(4)
                hasher.combine(value)
            case let .processingInstruction(target, data):
                hasher.combine(5)
                hasher.combine(target)
                hasher.combine(data)
            }
        }
    }
}

extension PureXML.Model.Node {
    /// Used by ``ElementStorage`` teardown: if this is an element whose backing
    /// storage this node solely owns, move its children into `pending` and clear
    /// them so the node releases flat; otherwise leave it untouched. Setting
    /// `self` aside before the uniqueness check drops this node's own hold on the
    /// storage, so the check counts only references held elsewhere (shared
    /// copy-on-write siblings), which must keep their subtree.
    mutating func drainUniquelyOwnedChildren(into pending: inout [Self]) {
        guard case var .element(element) = self else { return }
        self = .text("")
        if isKnownUniquelyReferenced(&element.storage), !element.storage.children.isEmpty {
            pending.append(contentsOf: element.storage.children)
            element.storage.children = []
        }
        self = .element(element)
    }
}
