public extension PureXML.XPath {
    /// A compiled XPath 1.0 expression: all thirteen axes with their
    /// abbreviations, the node tests, the operator grammar (`or`, `and`, `=`,
    /// `!=`, `<`, `<=`, `>`, `>=`, `+`, `-`, `*`, `div`, `mod`, unary `-`, `|`),
    /// number and string literals, variable references, function calls, and
    /// filter expressions, all over the four-type model (node-set, boolean,
    /// number, string). Reimplemented from the XPath 1.0 specification.
    struct Query: Sendable {
        let expression: Expression

        /// Compiles an XPath expression, throwing ``QueryError`` on a syntax error.
        public init(_ path: String) throws {
            expression = try Compiler.compile(path)
        }

        /// Evaluates the query over a node, returning the selected node-set in
        /// document order. A non-node-set expression yields an empty list; use
        /// ``value(over:variables:)`` for typed results.
        public func evaluate(over node: PureXML.Model.Node) -> [Selection] {
            Evaluator.evaluate(expression, over: node)
        }

        /// Evaluates the query with eval-time prefix bindings, so a name test like
        /// `x:foo` resolves `x` to its URI and matches by namespace regardless of
        /// the prefix the document uses.
        public func evaluate(over node: PureXML.Model.Node, namespaces: [String: String]) -> [Selection] {
            Evaluator.evaluate(expression, over: node, namespaces: namespaces)
        }

        /// Evaluates the query and returns the selected elements only.
        public func elements(over node: PureXML.Model.Node) -> [PureXML.Model.Element] {
            evaluate(over: node).compactMap(\.element)
        }

        /// Evaluates the query and returns the string-value of each selection.
        public func strings(over node: PureXML.Model.Node) -> [String] {
            evaluate(over: node).map(\.stringValue)
        }

        /// Evaluates the query to a typed ``Value`` with optional variable bindings.
        public func value(
            over node: PureXML.Model.Node,
            variables: [String: Value] = [:],
        ) throws -> Value {
            try Evaluator.value(expression, over: node, variables: variables)
        }

        /// Evaluates the query over a pre-built tree and returns the matched tree
        /// nodes in document order. Build the tree once (``PureXML/parseTree(_:)``)
        /// and query it repeatedly; pair with ``value(at:position:size:variables:)``
        /// to evaluate further expressions relative to each result.
        public func nodes(over root: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
            Evaluator.nodes(expression, over: root)
        }

        /// Evaluates the query against an explicit context: a node already in a
        /// tree (``PureXML/Model/TreeNode``), its one-based proximity `position`
        /// within a node-set of `size`, and variable bindings. Downstream engines
        /// (XSLT, Schematron) drive this per context node; `position()` and
        /// `last()` reflect the supplied values.
        public func value(
            at node: PureXML.Model.TreeNode,
            position: Int = 1,
            size: Int = 1,
            variables: [String: Value] = [:],
            namespaces: [String: String] = [:],
        ) throws -> Value {
            try Evaluator.value(expression, at: node, position: position, size: size, variables: variables, namespaces: namespaces)
        }

        /// Like ``value(at:position:size:variables:)`` but with an extra function
        /// table merged in (for engine-specific functions such as XSLT's `key`).
        func value(
            at node: PureXML.Model.TreeNode,
            position: Int,
            size: Int,
            variables: [String: Value],
            functions: FunctionTable,
        ) throws -> Value {
            try Evaluator.value(
                expression,
                at: node,
                position: position,
                size: size,
                variables: variables,
                functions: functions,
            )
        }

        /// Like ``nodes(over:)`` but with an extra function table merged in.
        func nodes(over root: PureXML.Model.TreeNode, functions: FunctionTable) -> [PureXML.Model.TreeNode] {
            Evaluator.nodes(expression, over: root, functions: functions)
        }

        /// Evaluates the query and coerces the result to a number.
        public func number(over node: PureXML.Model.Node, variables: [String: Value] = [:]) throws -> Double {
            try value(over: node, variables: variables).number
        }

        /// Evaluates the query and coerces the result to a string.
        public func string(over node: PureXML.Model.Node, variables: [String: Value] = [:]) throws -> String {
            try value(over: node, variables: variables).string
        }

        /// Evaluates the query and coerces the result to a boolean.
        public func boolean(over node: PureXML.Model.Node, variables: [String: Value] = [:]) throws -> Bool {
            try value(over: node, variables: variables).boolean
        }
    }
}
