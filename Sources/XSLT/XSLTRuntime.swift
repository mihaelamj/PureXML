extension PureXML.XSLT {
    /// The default ceiling on logical template-application nesting (see
    /// ``RecursionGuard``). The evaluator is iterative, so this is no longer a
    /// stack limit but a runaway guard: legitimate deep recursion (well into the
    /// thousands) succeeds, while an infinite or unbounded recursion, whose result
    /// tree would grow without bound, fails gracefully once it passes this depth.
    /// Configurable per transform.
    public static let defaultMaxTemplateDepth = 40000

    /// One produced item: a node for the result tree, or an attribute to attach to
    /// the enclosing element.
    enum ResultItem {
        case node(PureXML.Model.Node)
        case attribute(PureXML.Model.Attribute)
    }

    /// The evaluation context during instantiation.
    struct XSLTContext {
        var node: PureXML.Model.TreeNode
        /// The current node when it is not a tree node (an attribute or
        /// namespace node); `node` then holds its owner element.
        var current: PureXML.XPath.Node?
        var position: Int
        var size: Int
        var variables: [String: PureXML.XPath.Value]

        /// The XPath context node: `current` when set, else the tree node.
        var focus: PureXML.XPath.Node {
            current ?? .tree(node)
        }

        /// The mode of the template currently being instantiated, so `apply-imports`
        /// re-applies in the same mode.
        var mode: String?
        /// The import precedence of the template currently being instantiated, so
        /// `apply-imports` considers only templates below it. `.max` outside a template.
        var importPrecedence: Int
        /// The floor of the current template's stylesheet's import subtree;
        /// apply-imports searches [importRangeLow, importPrecedence).
        var importRangeLow: Int = 0
        /// The stylesheet xmlns bindings of the template being instantiated,
        /// so prefixed names in its expressions resolve by URI.
        var namespaces: [String: String] = [:]
        /// The base URI of the stylesheet element currently being instantiated
        /// (its template's or global variable's source file), against which a
        /// relative string-form `document()` reference resolves (XSLT 1.0 12.1).
        var baseURI: String = ""

        init(
            node: PureXML.Model.TreeNode,
            current: PureXML.XPath.Node? = nil,
            position: Int,
            size: Int,
            variables: [String: PureXML.XPath.Value],
            mode: String? = nil,
            importPrecedence: Int = .max,
            baseURI: String = "",
        ) {
            self.node = node
            self.current = current
            self.position = position
            self.size = size
            self.variables = variables
            self.mode = mode
            self.importPrecedence = importPrecedence
            self.baseURI = baseURI
        }
    }

    /// Shared, mutable signal that an `xsl:message terminate="yes"` fired, carrying
    /// its text. A reference type so the value-semantics transformer can set it.
    final class Termination {
        var message: String?
    }

    /// Shared, mutable latch for runaway template recursion. The evaluator is
    /// iterative, so deep recursion no longer overflows the stack; this instead
    /// caps the *logical* template-application depth (carried on each work item)
    /// so an unbounded or infinite recursion, whose result tree would grow without
    /// bound, fails gracefully rather than exhausting memory. `exceeded` latches
    /// once the depth passes `maxTemplateDepth`, so the work stack drains and the
    /// transform throws. A reference type so the value-semantics transformer can
    /// set it.
    final class RecursionGuard {
        var exceeded = false
    }
}
