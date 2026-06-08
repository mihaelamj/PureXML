extension PureXML.XPath {
    /// Evaluates a compiled ``Expression`` against a document, producing an XPath
    /// ``Value``. Location paths run over the parent-aware tree; the operator
    /// grammar, functions, and variables build on the four-type model.
    enum Evaluator {
        /// The full XPath 1.0 function library: the core functions plus the
        /// string, node, and number families.
        static let library = CoreFunctions.table
            .merging(StringFunctions.table)
            .merging(NodeFunctions.table)

        /// Evaluates an expression and returns its node-set as selections in
        /// document order. A non-node-set result yields an empty list; use
        /// ``value(_:over:variables:)`` for typed results.
        static func evaluate(_ expression: Expression, over node: PureXML.Model.Node) -> [Selection] {
            let context = rootContext(node, variables: [:])
            guard let value = try? eval(expression, context), case let .nodeSet(nodes) = value else {
                return []
            }
            return orderUnique(nodes).map(selection)
        }

        /// Evaluates an expression to a typed value with optional variable bindings.
        static func value(
            _ expression: Expression,
            over node: PureXML.Model.Node,
            variables: [String: Value],
        ) throws -> Value {
            try eval(expression, rootContext(node, variables: variables))
        }

        private static func rootContext(_ node: PureXML.Model.Node, variables: [String: Value]) -> EvaluationContext {
            let root = PureXML.Model.TreeNode(node)
            return EvaluationContext(
                node: .tree(root),
                position: 1,
                size: 1,
                variables: variables,
                functions: library,
            )
        }

        static func eval(_ expression: Expression, _ context: EvaluationContext) throws -> Value {
            switch expression {
            case let .number(value):
                return .number(value)
            case let .string(value):
                return .string(value)
            case let .variable(name):
                guard let value = context.variables[name] else { throw QueryError.undefinedVariable(name) }
                return value
            case let .negate(inner):
                return try .number(-eval(inner, context).number)
            case let .function(name, arguments):
                let values = try arguments.map { try eval($0, context) }
                return try context.functions.call(name, values, context)
            case let .union(left, right):
                return try .nodeSet(orderUnique(nodeSet(eval(left, context)) + nodeSet(eval(right, context))))
            case let .binary(oper, left, right):
                return try evalBinary(oper, left, right, context)
            case let .path(absolute, steps):
                return try evalPath(absolute: absolute, steps: steps, context)
            case let .filter(primary, predicates, steps):
                return try evalFilter(primary, predicates, steps, context)
            }
        }

        private static func evalPath(absolute: Bool, steps: [Step], _ context: EvaluationContext) throws -> Value {
            let start: Node = absolute ? root(of: context.node) : context.node
            return .nodeSet(orderUnique(evaluateSteps(steps, from: [start], context)))
        }

        private static func evalFilter(
            _ primary: Expression,
            _ predicates: [Expression],
            _ steps: [Step],
            _ context: EvaluationContext,
        ) throws -> Value {
            var nodes = try orderUnique(nodeSet(eval(primary, context)))
            nodes = try applyPredicates(predicates, to: nodes, context)
            if !steps.isEmpty {
                nodes = orderUnique(evaluateSteps(steps, from: nodes, context))
            }
            return .nodeSet(nodes)
        }

        // MARK: Node-set helpers

        static func nodeSet(_ value: Value) throws -> [Node] {
            guard case let .nodeSet(nodes) = value else {
                throw QueryError.invalidArguments("a node-set was expected")
            }
            return nodes
        }

        static func orderUnique(_ nodes: [Node]) -> [Node] {
            var seen: Set<Node> = []
            var unique: [Node] = []
            for node in nodes where seen.insert(node).inserted {
                unique.append(node)
            }
            return unique.sorted(by: Node.precedes)
        }

        private static func root(of node: Node) -> Node {
            var current = node
            while let parent = current.parent {
                current = parent
            }
            return current
        }

        private static func selection(_ node: Node) -> Selection {
            switch node {
            case let .tree(tree):
                return .node(tree.node)
            case let .attribute(_, attribute):
                return .attribute(attribute)
            case let .namespace(_, prefix, uri):
                let name = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)"
                return .attribute(PureXML.Model.Attribute(name, uri))
            }
        }
    }
}
