extension PureXML.XPath.Compiler {
    typealias Expression = PureXML.XPath.Expression
    typealias Step = PureXML.XPath.Step
    typealias Axis = PureXML.XPath.Axis
    typealias NodeTest = PureXML.XPath.NodeTest
    typealias QueryError = PureXML.XPath.QueryError

    // MARK: Paths and primaries

    mutating func parsePath() throws -> Expression {
        skipSpace()
        guard try isPrimaryStart() else {
            let (absolute, steps) = try parseLocationPath()
            return .path(absolute: absolute, steps: steps)
        }
        let primary = try parsePrimary()
        let predicates = try parsePredicates()
        var steps: [Step] = []
        skipSpace()
        if peek() == "/" {
            advance()
            if consume("/") {
                steps.append(Self.descendantOrSelfStep())
            }
            try steps.append(parseStep())
            try parseTrailingSteps(into: &steps)
        }
        if predicates.isEmpty, steps.isEmpty {
            return primary
        }
        return .filter(primary: primary, predicates: predicates, steps: steps)
    }

    private mutating func isPrimaryStart() throws -> Bool {
        guard let character = peek() else { return false }
        if character == "$" || character == "(" || character == "\"" || character == "'" {
            return true
        }
        if character.isNumber { return true }
        if character == ".", peek(1)?.isNumber == true { return true }
        return functionCallAhead()
    }

    private mutating func functionCallAhead() -> Bool {
        let save = index
        let word = parseName()
        skipSpace()
        let isCall = peek() == "("
        index = save
        return isCall && !word.isEmpty && !Self.isNodeType(word)
    }

    private static func isNodeType(_ name: String) -> Bool {
        ["node", "text", "comment", "processing-instruction"].contains(name)
    }

    private mutating func parsePrimary() throws -> Expression {
        skipSpace()
        if peek() == "$" {
            advance()
            return .variable(parseName())
        }
        if consume("(") {
            let expression = try parseExpression()
            skipSpace()
            try expect(")")
            return expression
        }
        if let quote = peek(), quote == "\"" || quote == "'" {
            return try .string(parseStringLiteral())
        }
        if let character = peek(), character.isNumber || character == "." {
            return .number(parseNumberLiteral())
        }
        return try parseFunctionCall()
    }

    private mutating func parseFunctionCall() throws -> Expression {
        let name = parseName()
        skipSpace()
        try expect("(")
        var arguments: [Expression] = []
        skipSpace()
        if peek() != ")" {
            try arguments.append(parseExpression())
            while skipSpaceThenComma() {
                try arguments.append(parseExpression())
            }
        }
        skipSpace()
        try expect(")")
        return .function(name: name, arguments: arguments)
    }

    private mutating func skipSpaceThenComma() -> Bool {
        skipSpace()
        return consume(",")
    }

    // MARK: Location paths

    static func descendantOrSelfStep() -> Step {
        Step(axis: .descendantOrSelf, test: .node, predicates: [])
    }

    private mutating func parseLocationPath() throws -> (absolute: Bool, steps: [Step]) {
        var absolute = false
        var steps: [Step] = []
        if consume("/") {
            absolute = true
            if consume("/") {
                steps.append(Self.descendantOrSelfStep())
                try steps.append(parseStep())
            } else if isAtEnd {
                return (true, [])
            } else {
                try steps.append(parseStep())
            }
        } else {
            try steps.append(parseStep())
        }
        try parseTrailingSteps(into: &steps)
        return (absolute, steps)
    }

    mutating func parseTrailingSteps(into steps: inout [Step]) throws {
        while true {
            skipSpace()
            guard peek() == "/" else { return }
            advance()
            if consume("/") {
                steps.append(Self.descendantOrSelfStep())
            }
            try steps.append(parseStep())
        }
    }

    private mutating func parseStep() throws -> Step {
        skipSpace()
        if matches("..") {
            advance(by: 2)
            return try Step(axis: .parent, test: .node, predicates: parsePredicates())
        }
        if peek() == ".", peek(1) != "." {
            advance()
            return try Step(axis: .selfAxis, test: .node, predicates: parsePredicates())
        }
        let axis = try parseAxis()
        let test = try parseNodeTest()
        return try Step(axis: axis, test: test, predicates: parsePredicates())
    }

    private mutating func parseAxis() throws -> Axis {
        if consume("@") {
            return .attribute
        }
        let save = index
        let word = parseName()
        if !word.isEmpty, matches("::") {
            advance(by: 2)
            return try Self.namedAxis(word)
        }
        index = save
        return .child
    }

    private static func namedAxis(_ name: String) throws -> Axis {
        if let axis = verticalAxis(name) ?? lateralAxis(name) {
            return axis
        }
        throw QueryError.unsupportedAxis(name)
    }

    private static func verticalAxis(_ name: String) -> Axis? {
        switch name {
        case "child": .child
        case "descendant": .descendant
        case "descendant-or-self": .descendantOrSelf
        case "parent": .parent
        case "ancestor": .ancestor
        case "ancestor-or-self": .ancestorOrSelf
        case "self": .selfAxis
        default: nil
        }
    }

    private static func lateralAxis(_ name: String) -> Axis? {
        switch name {
        case "following-sibling": .followingSibling
        case "preceding-sibling": .precedingSibling
        case "following": .following
        case "preceding": .preceding
        case "attribute": .attribute
        case "namespace": .namespace
        default: nil
        }
    }

    private mutating func parseNodeTest() throws -> NodeTest {
        skipSpace()
        if peek() == "*" {
            advance()
            return .wildcard
        }
        let name = parseName()
        guard !name.isEmpty else { throw QueryError.expectedNodeTest }
        guard peek() == "(" else {
            return .name(name)
        }
        return try parseNodeTypeTest(name)
    }

    private mutating func parseNodeTypeTest(_ name: String) throws -> NodeTest {
        advance()
        skipSpace()
        if name == "processing-instruction", peek() != ")" {
            let target = try parseStringLiteral()
            skipSpace()
            try expect(")")
            return .processingInstruction(target: target)
        }
        try expect(")")
        switch name {
        case "text": return .text
        case "node": return .node
        case "comment": return .comment
        case "processing-instruction": return .processingInstruction(target: nil)
        default: throw QueryError.unexpectedToken("\(name)()")
        }
    }

    private mutating func parsePredicates() throws -> [Expression] {
        var predicates: [Expression] = []
        while true {
            skipSpace()
            guard peek() == "[" else { return predicates }
            advance()
            try predicates.append(parseExpression())
            skipSpace()
            guard consume("]") else { throw QueryError.unterminatedPredicate }
        }
    }

    // MARK: Tokens

    mutating func parseStringLiteral() throws -> String {
        guard let quote = peek(), quote == "\"" || quote == "'" else {
            throw QueryError.unsupportedPredicate("expected a quoted value")
        }
        advance()
        var value = ""
        while let character = peek(), character != quote {
            value.append(character)
            advance()
        }
        guard peek() == quote else { throw QueryError.unsupportedPredicate("unterminated value") }
        advance()
        return value
    }

    private mutating func parseNumberLiteral() -> Double {
        var text = ""
        while let character = peek(), character.isNumber {
            text.append(character)
            advance()
        }
        if peek() == "." {
            text.append(".")
            advance()
            while let character = peek(), character.isNumber {
                text.append(character)
                advance()
            }
        }
        return Double(text) ?? .nan
    }

    mutating func parseName() -> String {
        var name = ""
        while let character = peek(), character.isXMLNameContinuation {
            if character == ":", peek(1) == ":" { break }
            name.append(character)
            advance()
        }
        return name
    }
}
