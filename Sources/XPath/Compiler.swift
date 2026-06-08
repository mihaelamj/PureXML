extension PureXML.XPath {
    /// Compiles an XPath location path into a list of steps. A small
    /// recursive-descent parser over the characters supporting the full axis set:
    /// the thirteen named axes (`ancestor::`, `following-sibling::`, …), the
    /// abbreviations `.`, `..`, `@`, `//`, the node tests (name, `*`, `text()`,
    /// `node()`, `comment()`, `processing-instruction()`), and the predicate
    /// subset `[n]`, `[@a]`, `[@a='v']`, `[child]`, `[child='v']`.
    struct Compiler {
        private let chars: [Character]
        private var index = 0

        private init(_ path: String) {
            chars = Array(path)
        }

        static func compile(_ path: String) throws -> (absolute: Bool, steps: [Step]) {
            var compiler = Compiler(path)
            return try compiler.parse()
        }

        private static func descendantOrSelfStep() -> Step {
            Step(axis: .descendantOrSelf, test: .node, predicates: [])
        }

        private mutating func parse() throws -> (absolute: Bool, steps: [Step]) {
            skipSpace()
            guard !isAtEnd else { throw QueryError.empty }
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

        private mutating func parseTrailingSteps(into steps: inout [Step]) throws {
            while true {
                skipSpace()
                if isAtEnd { return }
                guard consume("/") else {
                    throw QueryError.unexpectedToken(String(peek() ?? " "))
                }
                if consume("/") {
                    steps.append(Self.descendantOrSelfStep())
                }
                try steps.append(parseStep())
            }
        }

        private mutating func parseStep() throws -> Step {
            skipSpace()
            if matches("..") {
                advance()
                advance()
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
                advance()
                advance()
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
                let target = try parseLiteral()
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

        private mutating func parsePredicates() throws -> [Predicate] {
            var predicates: [Predicate] = []
            while peek() == "[" {
                advance()
                try predicates.append(parsePredicate())
            }
            return predicates
        }

        private mutating func parsePredicate() throws -> Predicate {
            skipSpace()
            let predicate = try parsePredicateBody()
            skipSpace()
            guard peek() == "]" else { throw QueryError.unterminatedPredicate }
            advance()
            return predicate
        }

        private mutating func parsePredicateBody() throws -> Predicate {
            if let digit = peek(), digit.isNumber {
                return .position(parseNumber())
            }
            if peek() == "@" {
                advance()
                let name = parseName()
                return try parseEquality(
                    makeEquals: { .attributeEquals(name: name, value: $0) },
                    makeExists: { .hasAttribute(name) },
                )
            }
            let name = parseName()
            guard !name.isEmpty else { throw QueryError.unsupportedPredicate("empty") }
            return try parseEquality(
                makeEquals: { .childEquals(name: name, value: $0) },
                makeExists: { .hasChild(name) },
            )
        }

        private mutating func parseEquality(
            makeEquals: (String) -> Predicate,
            makeExists: () -> Predicate,
        ) throws -> Predicate {
            skipSpace()
            guard peek() == "=" else { return makeExists() }
            advance()
            skipSpace()
            return try makeEquals(parseLiteral())
        }

        private mutating func parseLiteral() throws -> String {
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

        private mutating func parseName() -> String {
            var name = ""
            while let character = peek(), character.isXMLNameContinuation {
                // A `::` is the axis separator, not part of a QName, so stop
                // before it even though a single colon is a valid name character.
                if character == ":", peek(1) == ":" { break }
                name.append(character)
                advance()
            }
            return name
        }

        private mutating func parseNumber() -> Int {
            var digits = ""
            while let character = peek(), character.isNumber {
                digits.append(character)
                advance()
            }
            return Int(digits) ?? 0
        }

        private mutating func expect(_ character: Character) throws {
            guard peek() == character else {
                throw QueryError.unexpectedToken(String(peek() ?? " "))
            }
            advance()
        }

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek(_ ahead: Int = 0) -> Character? {
            let target = index + ahead
            return target < chars.count ? chars[target] : nil
        }

        private func matches(_ literal: String) -> Bool {
            let target = Array(literal)
            guard index + target.count <= chars.count else { return false }
            for (offset, character) in target.enumerated() where chars[index + offset] != character {
                return false
            }
            return true
        }

        @discardableResult
        private mutating func consume(_ literal: String) -> Bool {
            guard matches(literal) else { return false }
            index += literal.count
            return true
        }

        private mutating func advance() {
            if index < chars.count { index += 1 }
        }

        private mutating func skipSpace() {
            while let character = peek(), character == " " || character == "\t" {
                advance()
            }
        }
    }
}
