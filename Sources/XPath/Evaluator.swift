extension PureXML.XPath {
    /// Evaluates a compiled ``Expression`` against a document, producing an XPath
    /// ``Value``. Location paths run over the parent-aware tree; the operator
    /// grammar, functions, and variables build on the four-type model.
    enum Evaluator {
        /// The full XPath 1.0 function library: the core functions plus the
        /// string, node, and number families.
        nonisolated(unsafe) static let library = CoreFunctions.table
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
            return selections(orderUnique(nodes))
        }

        /// Evaluates an expression to a typed value with optional variable bindings.
        static func value(
            _ expression: Expression,
            over node: PureXML.Model.Node,
            variables: [String: Value],
        ) throws -> Value {
            try eval(expression, rootContext(node, variables: variables))
        }

        /// Evaluates a node-set expression against a pre-built tree and returns the
        /// matched tree nodes in document order (attribute and namespace results
        /// are dropped). Lets a caller build the tree once and query it repeatedly.
        static func nodes(
            _ expression: Expression,
            over root: PureXML.Model.TreeNode,
            functions: FunctionTable = FunctionTable(),
            namespaces: [String: String] = [:],
        ) -> [PureXML.Model.TreeNode] {
            let context = EvaluationContext(
                node: .tree(root),
                position: 1,
                size: 1,
                variables: [:],
                functions: library.merging(functions),
                namespaces: namespaces,
            )
            guard let value = try? eval(expression, context), case let .nodeSet(nodes) = value else {
                return []
            }
            return orderUnique(nodes).compactMap(\.treeNode)
        }

        /// Evaluates an expression against an explicit context: a node already in a
        /// tree, its proximity position and size, and variable bindings. This is
        /// the entry point downstream engines (XSLT, Schematron) drive per node.
        static func value(
            _ expression: Expression,
            at node: PureXML.Model.TreeNode,
            position: Int,
            size: Int,
            variables: [String: Value],
            functions: FunctionTable = FunctionTable(),
            namespaces: [String: String] = [:],
            budget: Budget? = nil,
        ) throws -> Value {
            try value(_: expression, atNode: .tree(node), position: position, size: size, variables: variables, functions: functions, namespaces: namespaces, budget: budget)
        }

        /// Like `value(_:at:...)` but starting from any XPath node, attributes
        /// and namespace nodes included (the XSLT current node can be either).
        static func value(
            _ expression: Expression,
            atNode node: Node,
            position: Int,
            size: Int,
            variables: [String: Value],
            functions: FunctionTable = FunctionTable(),
            namespaces: [String: String] = [:],
            budget: Budget? = nil,
        ) throws -> Value {
            let context = EvaluationContext(
                node: node,
                position: position,
                size: size,
                variables: variables,
                functions: library.merging(functions),
                namespaces: namespaces,
                budget: budget,
            )
            return try eval(expression, context)
        }

        /// Evaluates a node-set expression over a value tree with eval-time prefix
        /// bindings, returning the selected nodes in document order.
        static func evaluate(
            _ expression: Expression,
            over node: PureXML.Model.Node,
            namespaces: [String: String],
        ) -> [Selection] {
            let context = rootContext(node, variables: [:], namespaces: namespaces)
            guard let value = try? eval(expression, context), case let .nodeSet(nodes) = value else {
                return []
            }
            return selections(orderUnique(nodes))
        }

        private static func rootContext(
            _ node: PureXML.Model.Node,
            variables: [String: Value],
            namespaces: [String: String] = [:],
        ) -> EvaluationContext {
            let root = PureXML.Model.TreeNode(node)
            return EvaluationContext(
                node: .tree(root),
                position: 1,
                size: 1,
                variables: variables,
                functions: library,
                namespaces: namespaces,
            )
        }

        static func eval(_ expression: Expression, _ context: EvaluationContext) throws -> Value {
            switch expression {
            case let .number(value):
                return .number(value)
            case let .string(value):
                return .string(value)
            case let .variable(name):
                return try resolveVariable(name, context)
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

        /// The value bound to `$name`. A prefixed reference may be bound under its
        /// expanded name `{uri}local` (an XSLT variable is named by expanded
        /// QName): the raw key is tried first, so a caller's raw binding is
        /// unaffected, then the namespace-resolved name.
        private static func resolveVariable(_ name: String, _ context: EvaluationContext) throws -> Value {
            if let value = context.variables[name] { return value }
            if let expanded = expandedKey(name, context.namespaces), let value = context.variables[expanded] { return value }
            throw QueryError.undefinedVariable(name)
        }

        /// A prefixed name as its expanded key `{uri}local`, or nil when the name
        /// has no prefix or the prefix is unbound in `namespaces`.
        private static func expandedKey(_ name: String, _ namespaces: [String: String]) -> String? {
            guard let colon = name.firstIndex(of: ":"), let uri = namespaces[String(name[..<colon])] else { return nil }
            return "{\(uri)}\(name[name.index(after: colon)...])"
        }

        private static func evalPath(absolute: Bool, steps: [Step], _ context: EvaluationContext) throws -> Value {
            let start: Node = absolute ? root(of: context.node) : context.node
            let nodes = try evaluateSteps(steps, from: [start], context)
            // A single forward-axis step from the one start node yields nodes
            // already in document order with no duplicates (the axis produces
            // document order and cannot repeat a node from one context, and the
            // node test and predicates only filter), so the sort is redundant.
            // Otherwise sort: `evaluateSteps` is already duplicate-free (each step
            // de-duplicates or uses a per-context-disjoint axis), so only the
            // document-order sort is needed, not the `Set` de-duplication.
            if steps.count == 1, steps[0].axis.preservesDocumentOrderFromSingleContext {
                return .nodeSet(nodes)
            }
            return .nodeSet(nodes.sortedByDocumentOrder())
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
                // As in `evalPath`, `evaluateSteps` returns a duplicate-free set,
                // so the trailing path needs only the document-order sort.
                nodes = try evaluateSteps(steps, from: nodes, context).sortedByDocumentOrder()
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
            return unique.sortedByDocumentOrder()
        }

        private static func root(of node: Node) -> Node {
            var current = node
            while let parent = current.parent {
                current = parent
            }
            return current
        }

        /// Projects an ordered node-set to selections, sharing a projection memo
        /// so that result nodes nesting within one another reuse each other's
        /// already-built value `Node` subtrees rather than each rebuilding the
        /// whole subtree (which is quadratic for nested results).
        static func selections(_ nodes: [Node]) -> [Selection] {
            var memo: [ObjectIdentifier: PureXML.Model.Node] = [:]
            var result: [Selection] = []
            result.reserveCapacity(nodes.count)
            for node in nodes {
                result.append(selection(node, memo: &memo))
            }
            return result
        }

        private static func selection(_ node: Node, memo: inout [ObjectIdentifier: PureXML.Model.Node]) -> Selection {
            switch node {
            case let .tree(tree):
                return .node(tree.node(memo: &memo))
            case let .attribute(_, attribute):
                return .attribute(attribute)
            case let .namespace(_, prefix, uri):
                let name = prefix.isEmpty ? "xmlns" : "xmlns:\(prefix)"
                return .attribute(PureXML.Model.Attribute(name, uri))
            }
        }
    }
}
