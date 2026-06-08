/// One parsed step before element/attribute separation. File-scope and private:
/// an internal detail of ``PureXML/Pattern/PatternCompiler``.
private struct RawStep {
    let gap: PureXML.Pattern.Gap
    let isAttribute: Bool
    let test: PureXML.Pattern.NameMatch
}

extension PureXML.Pattern {
    /// Compiles a streaming-pattern string into element steps and an optional
    /// trailing attribute test. A small recursive-descent parser; constructs
    /// outside the streamable subset are rejected.
    struct PatternCompiler {
        private let chars: [Character]
        private var index = 0

        private init(_ pattern: String) {
            chars = Array(pattern)
        }

        static func compile(_ pattern: String) throws -> (elementSteps: [PatternStep], attributeTest: NameMatch?) {
            var compiler = PatternCompiler(pattern)
            return try compiler.parse()
        }

        private mutating func parse() throws -> (elementSteps: [PatternStep], attributeTest: NameMatch?) {
            guard !chars.isEmpty else { throw PatternError.empty }
            var steps: [RawStep] = []
            try steps.append(parseStep(gap: leadingGap()))
            while !isAtEnd {
                let gap: Gap
                if consume("//") {
                    gap = .descendant
                } else if consume("/") {
                    gap = .child
                } else {
                    throw PatternError.unsupported(String(peek() ?? " "))
                }
                try steps.append(parseStep(gap: gap))
            }
            return try assemble(steps)
        }

        private mutating func leadingGap() -> Gap {
            if consume("//") { return .descendant }
            if consume("/") { return .root }
            return .descendant
        }

        private func assemble(_ steps: [RawStep]) throws -> (elementSteps: [PatternStep], attributeTest: NameMatch?) {
            for (offset, step) in steps.enumerated() where step.isAttribute && offset != steps.count - 1 {
                throw PatternError.unsupported("an attribute step must be last")
            }
            if let last = steps.last, last.isAttribute {
                let elements = steps.dropLast().map { PatternStep(gap: $0.gap, test: $0.test) }
                return (Array(elements), last.test)
            }
            return (steps.map { PatternStep(gap: $0.gap, test: $0.test) }, nil)
        }

        private mutating func parseStep(gap: Gap) throws -> RawStep {
            guard let character = peek() else { throw PatternError.expectedStep }
            if character == "[" { throw PatternError.unsupported("predicate") }
            if character == "." { throw PatternError.unsupported(".") }
            let isAttribute = consume("@")
            let test = try parseTest()
            if peek() == "[" { throw PatternError.unsupported("predicate") }
            return RawStep(gap: gap, isAttribute: isAttribute, test: test)
        }

        private mutating func parseTest() throws -> NameMatch {
            if peek() == "*" {
                advance()
                return .wildcard
            }
            let name = parseName()
            guard !name.isEmpty else { throw PatternError.expectedStep }
            if name.hasSuffix(":"), peek() == "*" {
                advance()
                return .prefixWildcard(String(name.dropLast()))
            }
            return .name(name)
        }

        private mutating func parseName() -> String {
            var name = ""
            while let character = peek(), character.isXMLNameContinuation {
                name.append(character)
                advance()
            }
            return name
        }

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek() -> Character? {
            index < chars.count ? chars[index] : nil
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
    }
}
