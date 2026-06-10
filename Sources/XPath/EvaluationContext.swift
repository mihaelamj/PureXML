extension PureXML.XPath {
    /// One XPath function: it receives its already-evaluated argument values and
    /// the evaluation context, and returns a value.
    typealias FunctionImplementation = (_ arguments: [Value], _ context: EvaluationContext) throws -> Value

    /// The evaluation context an expression is evaluated against: the context
    /// node, its position and size within the current node-set, the variable
    /// bindings, and the function library. Predicates and the `position()` and
    /// `last()` functions read the position and size.
    struct EvaluationContext {
        var node: Node
        var position: Int
        var size: Int
        var variables: [String: Value]
        var functions: FunctionTable
        /// Prefix-to-URI bindings supplied at evaluation time, so a name test like
        /// `x:foo` resolves `x` to a URI and matches by namespace rather than by the
        /// document's own prefix. When any bindings are supplied the XPath 1.0
        /// rule applies exactly: an unprefixed name test selects only the null
        /// namespace. Empty by default, in which case matching falls back to
        /// the in-document prefix string.
        var namespaces: [String: String] = [:]

        /// A copy positioned on `node` at one-based `position` within a node-set of
        /// `size`, keeping the same variables, functions, and namespace bindings.
        func focused(on node: Node, position: Int, size: Int) -> EvaluationContext {
            EvaluationContext(
                node: node,
                position: position,
                size: size,
                variables: variables,
                functions: functions,
                namespaces: namespaces,
            )
        }
    }

    /// The XPath function library: a name-to-implementation table. The core set is
    /// built in; further functions extend it.
    struct FunctionTable {
        private var table: [String: FunctionImplementation]

        init(_ table: [String: FunctionImplementation] = [:]) {
            self.table = table
        }

        /// Returns a table with `implementation` registered under `name`.
        func adding(_ name: String, _ implementation: @escaping FunctionImplementation) -> FunctionTable {
            var copy = table
            copy[name] = implementation
            return FunctionTable(copy)
        }

        /// Merges another table's entries over this one's.
        func merging(_ other: FunctionTable) -> FunctionTable {
            FunctionTable(table.merging(other.table) { _, new in new })
        }

        func call(_ name: String, _ arguments: [Value], _ context: EvaluationContext) throws -> Value {
            if let implementation = table[name] {
                return try implementation(arguments, context)
            }
            // A prefixed name may be an EXSLT extension function: resolve the prefix
            // to its namespace URI and dispatch by namespace.
            if let colon = name.firstIndex(of: ":") {
                let prefix = String(name[..<colon])
                let local = String(name[name.index(after: colon)...])
                if let uri = context.namespaces[prefix], let implementation = EXSLT.implementation(uri: uri, local: local) {
                    return try implementation(arguments, context)
                }
            }
            throw QueryError.unknownFunction(name)
        }
    }
}
