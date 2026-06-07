public extension PureXML.XPath {
    /// A compiled XPath location-path query over the supported subset: the
    /// forward axes (child, descendant `//`, self `.`, attribute `@`), the node
    /// tests (name, `*`, `text()`, `node()`, `comment()`), and the predicates
    /// `[n]`, `[@a]`, `[@a='v']`, `[child]`, `[child='v']`.
    ///
    /// Upward and sibling axes, functions, and the full expression language are
    /// intentionally out of scope. Reimplemented from the XPath 1.0 specification.
    struct Query: Sendable {
        let absolute: Bool
        let steps: [Step]

        /// Compiles an XPath location path, throwing ``QueryError`` on a path
        /// outside the supported subset.
        public init(_ path: String) throws {
            (absolute, steps) = try Compiler.compile(path)
        }

        /// Evaluates the query over a node, returning the selected node-set in
        /// document order. The node is the starting context.
        public func evaluate(over node: PureXML.Model.Node) throws -> [Selection] {
            try Evaluator.evaluate(steps: steps, over: node)
        }

        /// Evaluates the query and returns the selected elements only.
        public func elements(over node: PureXML.Model.Node) throws -> [PureXML.Model.Element] {
            try evaluate(over: node).compactMap(\.element)
        }

        /// Evaluates the query and returns the string-value of each selection.
        public func strings(over node: PureXML.Model.Node) throws -> [String] {
            try evaluate(over: node).map(\.stringValue)
        }
    }
}
