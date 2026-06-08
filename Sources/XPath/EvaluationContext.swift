extension PureXML.XPath {
    /// One XPath function: it receives its already-evaluated argument values and
    /// the evaluation context, and returns a value.
    typealias FunctionImplementation = @Sendable (_ arguments: [Value], _ context: EvaluationContext) throws -> Value

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

        /// A copy positioned on `node` at one-based `position` within a node-set of
        /// `size`, keeping the same variables and functions.
        func focused(on node: Node, position: Int, size: Int) -> EvaluationContext {
            EvaluationContext(
                node: node,
                position: position,
                size: size,
                variables: variables,
                functions: functions,
            )
        }
    }

    /// The XPath function library: a name-to-implementation table. The core set is
    /// built in; further functions extend it.
    struct FunctionTable: Sendable {
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
            guard let implementation = table[name] else {
                throw QueryError.unknownFunction(name)
            }
            return try implementation(arguments, context)
        }
    }
}
