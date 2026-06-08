extension PureXML.XPath {
    /// A binary operator of the XPath expression language, grouped by the
    /// precedence level its parser method handles.
    enum BinaryOperator: Equatable {
        case logicalOr
        case logicalAnd
        case equal
        case notEqual
        case lessThan
        case lessOrEqual
        case greaterThan
        case greaterOrEqual
        case add
        case subtract
        case multiply
        case divide
        case modulo
    }

    /// A compiled XPath expression. A bare location path is ``path``; the operator
    /// grammar, function calls, variables, and filter expressions build on it.
    indirect enum Expression: Equatable, Sendable {
        /// A location path: absolute when rooted, with its ordered steps.
        case path(absolute: Bool, steps: [Step])
        /// A binary operation.
        case binary(BinaryOperator, Expression, Expression)
        /// Unary minus.
        case negate(Expression)
        /// A node-set union (`|`).
        case union(Expression, Expression)
        /// A numeric literal.
        case number(Double)
        /// A string literal.
        case string(String)
        /// A function call.
        case function(name: String, arguments: [Expression])
        /// A variable reference (`$name`).
        case variable(String)
        /// A primary expression with predicates and an optional trailing path
        /// (`(expr)[p]/step`, `id('x')/step`).
        case filter(primary: Expression, predicates: [Expression], steps: [Step])
    }
}
