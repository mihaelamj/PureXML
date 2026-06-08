extension PureXML.XPath {
    /// Compiles an XPath expression into an ``Expression`` tree. A recursive
    /// descent parser whose grammatical position disambiguates the tokens XPath
    /// overloads: `*` is a wildcard in a node test but multiplication after an
    /// operand, and `div`/`mod`/`and`/`or` are operator names only where an
    /// operator is expected. The path, primary, and token parsing live in a
    /// companion file. Reimplemented from the XPath 1.0 grammar.
    struct Compiler {
        let chars: [Character]
        var index = 0

        private init(_ path: String) {
            chars = Array(path)
        }

        static func compile(_ path: String) throws -> Expression {
            var compiler = Compiler(path)
            compiler.skipSpace()
            guard !compiler.isAtEnd else { throw QueryError.empty }
            let expression = try compiler.parseExpression()
            compiler.skipSpace()
            guard compiler.isAtEnd else {
                throw QueryError.unexpectedToken(String(compiler.peek() ?? " "))
            }
            return expression
        }

        // MARK: Operator precedence ladder

        mutating func parseExpression() throws -> Expression {
            try parseOr()
        }

        private mutating func parseOr() throws -> Expression {
            var left = try parseAnd()
            while peekKeyword("or") {
                advance(by: 2)
                left = try .binary(.logicalOr, left, parseAnd())
            }
            return left
        }

        private mutating func parseAnd() throws -> Expression {
            var left = try parseEquality()
            while peekKeyword("and") {
                advance(by: 3)
                left = try .binary(.logicalAnd, left, parseEquality())
            }
            return left
        }

        private mutating func parseEquality() throws -> Expression {
            var left = try parseRelational()
            while true {
                skipSpace()
                if consume("!=") {
                    left = try .binary(.notEqual, left, parseRelational())
                } else if peek() == "=" {
                    advance()
                    left = try .binary(.equal, left, parseRelational())
                } else {
                    return left
                }
            }
        }

        private mutating func parseRelational() throws -> Expression {
            var left = try parseAdditive()
            while let look = relationalOperator() {
                left = try .binary(look, left, parseAdditive())
            }
            return left
        }

        private mutating func relationalOperator() -> BinaryOperator? {
            skipSpace()
            if consume("<=") { return .lessOrEqual }
            if consume(">=") { return .greaterOrEqual }
            if peek() == "<" {
                advance()
                return .lessThan
            }
            if peek() == ">" {
                advance()
                return .greaterThan
            }
            return nil
        }

        private mutating func parseAdditive() throws -> Expression {
            var left = try parseMultiplicative()
            while true {
                skipSpace()
                if peek() == "+" {
                    advance()
                    left = try .binary(.add, left, parseMultiplicative())
                } else if peek() == "-" {
                    advance()
                    left = try .binary(.subtract, left, parseMultiplicative())
                } else {
                    return left
                }
            }
        }

        private mutating func parseMultiplicative() throws -> Expression {
            var left = try parseUnary()
            while let look = multiplicativeOperator() {
                left = try .binary(look, left, parseUnary())
            }
            return left
        }

        private mutating func multiplicativeOperator() -> BinaryOperator? {
            skipSpace()
            if peek() == "*" {
                advance()
                return .multiply
            }
            if peekKeyword("div") {
                advance(by: 3)
                return .divide
            }
            if peekKeyword("mod") {
                advance(by: 3)
                return .modulo
            }
            return nil
        }

        private mutating func parseUnary() throws -> Expression {
            skipSpace()
            if peek() == "-" {
                advance()
                return try .negate(parseUnary())
            }
            return try parseUnion()
        }

        private mutating func parseUnion() throws -> Expression {
            var left = try parsePath()
            while true {
                skipSpace()
                guard peek() == "|" else { return left }
                advance()
                left = try .union(left, parsePath())
            }
        }

        // MARK: Cursor

        mutating func expect(_ character: Character) throws {
            guard peek() == character else {
                throw QueryError.unexpectedToken(String(peek() ?? " "))
            }
            advance()
        }

        var isAtEnd: Bool {
            index >= chars.count
        }

        func peek(_ ahead: Int = 0) -> Character? {
            let target = index + ahead
            return target < chars.count ? chars[target] : nil
        }

        /// Whether `word` appears next as a whole token (not followed by a name
        /// character), used to read operator keywords in operator position.
        func peekKeyword(_ word: String) -> Bool {
            guard matches(word) else { return false }
            if let after = peek(word.count), after.isXMLNameContinuation { return false }
            return true
        }

        func matches(_ literal: String) -> Bool {
            let target = Array(literal)
            guard index + target.count <= chars.count else { return false }
            for (offset, character) in target.enumerated() where chars[index + offset] != character {
                return false
            }
            return true
        }

        @discardableResult
        mutating func consume(_ literal: String) -> Bool {
            guard matches(literal) else { return false }
            index += literal.count
            return true
        }

        mutating func advance(by count: Int = 1) {
            index = Swift.min(index + count, chars.count)
        }

        mutating func skipSpace() {
            while let character = peek(), character == " " || character == "\t" || character == "\n" || character == "\r" {
                advance()
            }
        }
    }
}
