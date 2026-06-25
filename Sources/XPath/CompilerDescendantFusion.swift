extension PureXML.XPath.Compiler {
    /// Fuses each `descendant-or-self::node()` step immediately followed by a
    /// `child::X` step into a single `descendant::X` step. This is the standard
    /// `//` rewrite: `descendant-or-self::node()/child::X` selects exactly the
    /// `X` descendants of the context, the same node-set as `descendant::X`, but
    /// without materializing every node of the subtree as an intermediate
    /// context. The compiled step list is rewritten once, so every evaluation of
    /// the query benefits.
    ///
    /// The rewrite is applied only when the child step's predicates are
    /// non-positional. A positional predicate filters relative to each parent's
    /// own child list (`//x[1]` is the first `x` child of EACH element, not the
    /// first `x` in document order), which the `descendant` axis cannot
    /// reproduce, so such a pair is left exactly as the grammar produced it.
    static func fuseDescendantSteps(_ steps: [Step]) -> [Step] {
        guard steps.count >= 2 else { return steps }
        var result: [Step] = []
        result.reserveCapacity(steps.count)
        var index = 0
        while index < steps.count {
            let step = steps[index]
            if index + 1 < steps.count, isDescendantOrSelfNode(step) {
                let child = steps[index + 1]
                if child.axis == .child, child.predicates.allSatisfy(isNonPositionalPredicate) {
                    result.append(Step(axis: .descendant, test: child.test, predicates: child.predicates))
                    index += 2
                    continue
                }
            }
            result.append(step)
            index += 1
        }
        return result
    }

    /// The bare `descendant-or-self::node()` step that `//` compiles to.
    private static func isDescendantOrSelfNode(_ step: Step) -> Bool {
        step.axis == .descendantOrSelf && step.test == .node && step.predicates.isEmpty
    }

    /// Whether `predicate` is safe to carry from a `child` axis onto a
    /// `descendant` axis. Safe exactly when it is not a positional filter: its
    /// value is provably a boolean, node-set, or string (never a number, which
    /// XPath reads as `position() = value`), AND it nowhere references
    /// `position()` or `last()` (so `[position() < 3]`, a boolean, is still
    /// excluded). Anything not provably both is treated as positional and left
    /// unfused, so the optimization can never change a result.
    private static func isNonPositionalPredicate(_ predicate: Expression) -> Bool {
        isBooleanValued(predicate) && !referencesPosition(predicate)
    }

    /// Whether the expression's value is provably a boolean, node-set, or string
    /// (never a number). A relational or logical operator and the known
    /// boolean-returning functions yield booleans; a path, filter, or union
    /// yields a node-set; a literal string yields a string. A number, a
    /// variable (type unknown at compile time), a unary minus, an arithmetic
    /// operator, and an unrecognized function are not provably non-numeric.
    private static func isBooleanValued(_ expression: Expression) -> Bool {
        switch expression {
        case let .binary(binaryOperator, _, _):
            switch binaryOperator {
            case .logicalOr, .logicalAnd, .equal, .notEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                true
            case .add, .subtract, .multiply, .divide, .modulo:
                false
            }
        case .union, .path, .filter, .string:
            true
        case let .function(name, _):
            booleanReturningFunctions.contains(name)
        case .number, .variable, .negate:
            false
        }
    }

    /// The built-in functions that return a boolean (so a predicate calling one
    /// is a boolean test, never a position test). INVARIANT: every name here must
    /// be position- and size-independent. `referencesPosition` scans only for the
    /// `position()`/`last()` syntax, so a function that reads the context position
    /// or size INTERNALLY (without taking it as a visible argument) would defeat
    /// the guard and let a positional predicate ride the descendant axis. Do not
    /// add such a function to this set.
    private static let booleanReturningFunctions: Set<String> = [
        "boolean", "not", "true", "false", "lang", "contains", "starts-with",
    ]

    /// Whether the expression references `position()` or `last()` anywhere,
    /// scanned conservatively through every sub-expression (including nested
    /// path and filter predicates, whose own context the functions actually
    /// bind to). Over-inclusive on purpose: a false positive only declines a
    /// fusion, never produces a wrong result.
    private static func referencesPosition(_ expression: Expression) -> Bool {
        switch expression {
        case let .function(name, arguments):
            name == "position" || name == "last" || arguments.contains(where: referencesPosition)
        case let .binary(_, lhs, rhs):
            referencesPosition(lhs) || referencesPosition(rhs)
        case let .negate(operand):
            referencesPosition(operand)
        case let .union(lhs, rhs):
            referencesPosition(lhs) || referencesPosition(rhs)
        case let .path(_, steps):
            steps.contains { $0.predicates.contains(where: referencesPosition) }
        case let .filter(primary, predicates, steps):
            referencesPosition(primary)
                || predicates.contains(where: referencesPosition)
                || steps.contains { $0.predicates.contains(where: referencesPosition) }
        case .number, .string, .variable:
            false
        }
    }
}
