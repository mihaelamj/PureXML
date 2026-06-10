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
        /// A `<!DOCTYPE>` node, carried as a child of the document rather than out
        /// of band. Its `name` is the document type (root element) name, `value`
        /// is the internal subset text, and the public and system identifiers are
        /// held as `public`/`system` attributes.
        case doctype
        /// An `&name;` reference kept unexpanded as a node, with its replacement
        /// content as `children` (the DOM `EntityReference` model). `name` is the
        /// entity name; `value` is the replacement text for quick access.
        case entityReference
        /// A namespace binding as a node (the DOM `Namespace` model and the XPath
        /// namespace axis): `name`'s local part is the prefix (empty for the
        /// default namespace) and `value` is the namespace URI.
        case namespace
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
    ///
    /// Ownership: because parents are weak, keep a reference to the tree's root
    /// (or a node's ``ownerDocument``) while using any node inside it; a child
    /// held on its own loses its ancestry the moment the rest of the tree is
    /// released. Concurrency: `TreeNode` is deliberately not `Sendable`; it has
    /// no internal synchronization, so confine a tree to one thread or actor and
    /// cross concurrency boundaries with the immutable, `Sendable` ``Node``
    /// projection (``node``) instead.
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
        /// The node's span in the source text, when it was produced by the ranged
        /// reader (``PureXML/read(asTree:)``); nil for synthesized or edited nodes.
        /// Lets a located finding be mapped back to characters in the document.
        public internal(set) var sourceRange: PureXML.Parsing.SourceRange?
        /// For an element, the span between its start tag and end tag (where
        /// children live), so a quick-fix can place an inserted attribute (just
        /// before `contentRange.start`) or child (at `contentRange.end`). Nil for
        /// self-closing or non-element nodes.
        public internal(set) var contentRange: PureXML.Parsing.SourceRange?

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

        /// Creates a `<!DOCTYPE>` node for the given root element name, with an
        /// optional external identifier and internal subset text.
        public static func doctype(
            name: String,
            publicID: String? = nil,
            systemID: String? = nil,
            internalSubset: String = "",
        ) -> TreeNode {
            var attributes: [PureXML.Model.Attribute] = []
            if let publicID { attributes.append(PureXML.Model.Attribute("public", publicID)) }
            if let systemID { attributes.append(PureXML.Model.Attribute("system", systemID)) }
            return TreeNode(kind: .doctype, name: PureXML.Model.QualifiedName(name), attributes: attributes, value: internalSubset)
        }

        /// Creates an `&name;` entity-reference node whose `children` are its
        /// replacement content. `value` mirrors the children's text for quick use.
        public static func entityReference(_ name: String, children: [TreeNode] = []) -> TreeNode {
            let node = TreeNode(kind: .entityReference, name: PureXML.Model.QualifiedName(name), children: children)
            node.value = children.reduce(into: "") { $0 += $1.stringValue }
            return node
        }

        /// Creates a namespace node binding `prefix` (empty for the default
        /// namespace) to `uri`.
        public static func namespace(prefix: String, uri: String) -> TreeNode {
            TreeNode(kind: .namespace, name: PureXML.Model.QualifiedName(prefix), value: uri)
        }
    }
}
