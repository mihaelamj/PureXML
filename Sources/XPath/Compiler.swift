extension PureXML.XPath {
    /// Compiles an XPath location-path string (the supported subset) into a list
    /// of steps. A small recursive-descent parser over the characters.
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

        private mutating func parse() throws -> (absolute: Bool, steps: [Step]) {
            skipSpace()
            guard !isAtEnd else { throw QueryError.empty }
            var absolute = false
            var steps: [Step] = []

            if peek() == "/" {
                absolute = true
                advance()
                if peek() == "/" {
                    advance()
                    try steps.append(parseStep(axisOverride: .descendant))
                } else if isAtEnd {
                    return (true, [])
                } else {
                    try steps.append(parseStep(axisOverride: nil))
                }
            } else {
                try steps.append(parseStep(axisOverride: nil))
            }

            while true {
                skipSpace()
                guard peek() == "/" else {
                    if isAtEnd { break }
                    throw QueryError.unexpectedToken(String(peek() ?? " "))
                }
                advance()
                if peek() == "/" {
                    advance()
                    try steps.append(parseStep(axisOverride: .descendant))
                } else {
                    try steps.append(parseStep(axisOverride: nil))
                }
            }
            return (absolute, steps)
        }

        private mutating func parseStep(axisOverride: Axis?) throws -> Step {
            skipSpace()
            if peek() == "." {
                advance()
                if peek() == "." {
                    throw QueryError.unsupportedAxis("..")
                }
                return try Step(axis: .selfNode, test: .node, predicates: parsePredicates())
            }
            var axis = axisOverride ?? .child
            if peek() == "@" {
                advance()
                axis = .attribute
            }
            let test = try parseNodeTest()
            return try Step(axis: axis, test: test, predicates: parsePredicates())
        }

        private mutating func parseNodeTest() throws -> NodeTest {
            if peek() == "*" {
                advance()
                return .wildcard
            }
            let name = parseName()
            guard !name.isEmpty else { throw QueryError.expectedNodeTest }
            if peek() == "(" {
                advance()
                skipSpace()
                guard peek() == ")" else { throw QueryError.unexpectedToken(String(peek() ?? " ")) }
                advance()
                switch name {
                case "text": return .text
                case "node": return .node
                case "comment": return .comment
                default: throw QueryError.unexpectedToken("\(name)()")
                }
            }
            return .name(name)
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
            let predicate: Predicate
            if let digit = peek(), digit.isNumber {
                predicate = .position(parseNumber())
            } else if peek() == "@" {
                advance()
                let name = parseName()
                predicate = try parseEquality(
                    makeEquals: { .attributeEquals(name: name, value: $0) },
                    makeExists: { .hasAttribute(name) },
                )
            } else {
                let name = parseName()
                guard !name.isEmpty else { throw QueryError.unsupportedPredicate("empty") }
                predicate = try parseEquality(
                    makeEquals: { .childEquals(name: name, value: $0) },
                    makeExists: { .hasChild(name) },
                )
            }
            skipSpace()
            guard peek() == "]" else { throw QueryError.unterminatedPredicate }
            advance()
            return predicate
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

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
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
