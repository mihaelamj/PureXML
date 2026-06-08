extension PureXML.XPath.Evaluator {
    typealias BinaryOperator = PureXML.XPath.BinaryOperator

    static func evalBinary(
        _ oper: BinaryOperator,
        _ left: Expression,
        _ right: Expression,
        _ context: EvaluationContext,
    ) throws -> Value {
        switch oper {
        case .logicalOr:
            try .boolean(eval(left, context).boolean || eval(right, context).boolean)
        case .logicalAnd:
            try .boolean(eval(left, context).boolean && eval(right, context).boolean)
        case .add, .subtract, .multiply, .divide, .modulo:
            try .number(arithmetic(oper, eval(left, context).number, eval(right, context).number))
        case .equal, .notEqual:
            try .boolean(equality(eval(left, context), eval(right, context), negate: oper == .notEqual))
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            try .boolean(relational(eval(left, context), eval(right, context), oper))
        }
    }

    private static func arithmetic(_ oper: BinaryOperator, _ lhs: Double, _ rhs: Double) -> Double {
        switch oper {
        case .add: lhs + rhs
        case .subtract: lhs - rhs
        case .multiply: lhs * rhs
        case .divide: lhs / rhs
        case .modulo: lhs.truncatingRemainder(dividingBy: rhs)
        default: .nan
        }
    }

    // MARK: Equality

    private static func equality(_ lhs: Value, _ rhs: Value, negate: Bool) -> Bool {
        switch (lhs, rhs) {
        case let (.nodeSet(left), .nodeSet(right)):
            nodeSetEquality(left, right, negate: negate)
        case let (.nodeSet(nodes), scalar):
            nodeSetScalarEquality(nodes, scalar, negate: negate)
        case let (scalar, .nodeSet(nodes)):
            nodeSetScalarEquality(nodes, scalar, negate: negate)
        default:
            scalarEquality(lhs, rhs, negate: negate)
        }
    }

    private static func nodeSetEquality(_ left: [Node], _ right: [Node], negate: Bool) -> Bool {
        let rightStrings = right.map(\.stringValue)
        for value in left.map(\.stringValue) {
            for other in rightStrings where (value == other) != negate {
                return true
            }
        }
        return false
    }

    private static func nodeSetScalarEquality(_ nodes: [Node], _ scalar: Value, negate: Bool) -> Bool {
        switch scalar {
        case let .boolean(flag):
            (!nodes.isEmpty == flag) != negate
        case let .number(number):
            nodes.contains { (PureXML.XPath.Value.parseNumber($0.stringValue) == number) != negate }
        case let .string(text):
            nodes.contains { ($0.stringValue == text) != negate }
        case .nodeSet:
            false
        }
    }

    private static func scalarEquality(_ lhs: Value, _ rhs: Value, negate: Bool) -> Bool {
        let equal: Bool = if case .boolean = lhs { lhs.boolean == rhs.boolean } else if case .boolean = rhs {
            lhs.boolean == rhs.boolean
        } else if case .number = lhs { lhs.number == rhs.number } else if case .number = rhs {
            lhs.number == rhs.number
        } else {
            lhs.string == rhs.string
        }
        return equal != negate
    }

    // MARK: Relational

    private static func relational(_ lhs: Value, _ rhs: Value, _ oper: BinaryOperator) -> Bool {
        let lefts = numbers(of: lhs)
        let rights = numbers(of: rhs)
        for left in lefts {
            for right in rights where numericCompare(left, right, oper) {
                return true
            }
        }
        return false
    }

    private static func numbers(of value: Value) -> [Double] {
        if case let .nodeSet(nodes) = value {
            return nodes.map { PureXML.XPath.Value.parseNumber($0.stringValue) }
        }
        return [value.number]
    }

    private static func numericCompare(_ lhs: Double, _ rhs: Double, _ oper: BinaryOperator) -> Bool {
        switch oper {
        case .lessThan: lhs < rhs
        case .lessOrEqual: lhs <= rhs
        case .greaterThan: lhs > rhs
        case .greaterOrEqual: lhs >= rhs
        default: false
        }
    }
}
