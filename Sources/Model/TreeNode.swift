public extension PureXML.Model {
    /// The kind of a ``TreeNode``, mirroring ``Node``'s cases. Carried as a tag
    /// so a node can be navigated and edited uniformly regardless of kind.
    enum TreeNodeKind: Equatable, Sendable {
        case document
        case element
        case text
        case cdata
        case comment
        case processingInstruction
    }

    /// A mutable, parent-aware XML tree node (the libxml2 `tree.h` model).
    ///
    /// Unlike the value-typed ``Node``, which is immutable and holds no upward
    /// links, a `TreeNode` is a reference type that knows its parent and siblings,
    /// so a document can be navigated in every direction and edited in place:
    /// insert, remove, replace, and copy. Children are held strongly and the
    /// parent weakly, so a detached subtree is freed once no one references it.
    ///
    /// Build one from a parsed ``Node`` with ``init(_:)`` and convert back with
    /// ``node`` to serialize. A node has exactly one parent: attaching a node that
    /// already has one detaches it first, so the tree can never become a DAG.
    final class TreeNode {
        /// The node kind. Fixed for a node's lifetime; change kind by replacing
        /// the node.
        public let kind: PureXML.Model.TreeNodeKind
        /// The element name (or the processing-instruction target), or nil for
        /// text, CDATA, comment, and document nodes.
        public var name: PureXML.Model.QualifiedName?
        /// The element's attributes; empty for non-element nodes.
        public var attributes: [PureXML.Model.Attribute]
        /// The character payload: text/CDATA/comment content, or PI data. Empty
        /// for element and document nodes.
        public var value: String
        /// The parent node, or nil for a root or detached node. Held weakly.
        public internal(set) weak var parent: TreeNode?
        /// The child nodes in document order. Mutated only through the editing
        /// methods so the parent links stay consistent.
        public internal(set) var children: [TreeNode]

        init(
            kind: PureXML.Model.TreeNodeKind,
            name: PureXML.Model.QualifiedName? = nil,
            attributes: [PureXML.Model.Attribute] = [],
            value: String = "",
            children: [TreeNode] = [],
        ) {
            self.kind = kind
            self.name = name
            self.attributes = attributes
            self.value = value
            self.children = []
            for child in children {
                append(child)
            }
        }

        // MARK: Factories

        /// Creates a document node holding the given top-level children.
        public static func document(children: [TreeNode] = []) -> TreeNode {
            TreeNode(kind: .document, children: children)
        }

        /// Creates an element node.
        public static func element(
            _ name: PureXML.Model.QualifiedName,
            attributes: [PureXML.Model.Attribute] = [],
            children: [TreeNode] = [],
        ) -> TreeNode {
            TreeNode(kind: .element, name: name, attributes: attributes, children: children)
        }

        /// Creates an element node from a raw `prefix:local` name.
        public static func element(
            _ name: String,
            attributes: [PureXML.Model.Attribute] = [],
            children: [TreeNode] = [],
        ) -> TreeNode {
            element(PureXML.Model.QualifiedName(name), attributes: attributes, children: children)
        }

        /// Creates a text node.
        public static func text(_ value: String) -> TreeNode {
            TreeNode(kind: .text, value: value)
        }

        /// Creates a CDATA-section node.
        public static func cdata(_ value: String) -> TreeNode {
            TreeNode(kind: .cdata, value: value)
        }

        /// Creates a comment node.
        public static func comment(_ value: String) -> TreeNode {
            TreeNode(kind: .comment, value: value)
        }

        /// Creates a processing-instruction node.
        public static func processingInstruction(target: String, data: String) -> TreeNode {
            TreeNode(kind: .processingInstruction, name: PureXML.Model.QualifiedName(target), value: data)
        }
    }
}
