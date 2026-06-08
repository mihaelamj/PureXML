public extension PureXML.XPath {
    /// A compiled XPath location-path query: all thirteen axes (`child`,
    /// `descendant`, `parent`, `ancestor`, `following-sibling`,
    /// `preceding-sibling`, `following`, `preceding`, `attribute`, `namespace`,
    /// `self`, `descendant-or-self`, `ancestor-or-self`) with their abbreviations
    /// (`.`, `..`, `@`, `//`), the node tests (name, `*`, `text()`, `node()`,
    /// `comment()`, `processing-instruction()`), and the predicate subset `[n]`,
    /// `[@a]`, `[@a='v']`, `[child]`, `[child='v']`.
    ///
    /// The expression language (operators, the full function library, variables)
    /// arrives in later steps. Reimplemented from the XPath 1.0 specification.
    struct Query: Sendable {
        let absolute: Bool
        let steps: [Step]

        /// Compiles an XPath location path, throwing ``QueryError`` on a path
        /// outside the supported grammar.
        public init(_ path: String) throws {
            (absolute, steps) = try Compiler.compile(path)
        }

        /// Evaluates the query over a node, returning the selected node-set in
        /// document order. The node is the starting context.
        public func evaluate(over node: PureXML.Model.Node) -> [Selection] {
            Evaluator.evaluate(steps: steps, over: node)
        }

        /// Evaluates the query and returns the selected elements only.
        public func elements(over node: PureXML.Model.Node) -> [PureXML.Model.Element] {
            evaluate(over: node).compactMap(\.element)
        }

        /// Evaluates the query and returns the string-value of each selection.
        public func strings(over node: PureXML.Model.Node) -> [String] {
            evaluate(over: node).map(\.stringValue)
        }
    }
}
