/// One member of a character class: a single scalar (a possible range endpoint)
/// or a named sub-class. File-scope and private.
private enum ClassMember {
    case scalar(Unicode.Scalar)
    case named(PureXML.Regex.NamedClass)
    case negatedNamed(PureXML.Regex.NamedClass)
    case category(PureXML.Regex.CategoryPredicate)
}

extension PureXML.Regex {
    /// Recursive-descent parser for the XML Schema regular-expression grammar,
    /// producing a ``Node`` tree. Anchoring is implicit (the whole string is
    /// matched), so `^` and `$` are ordinary characters.
    struct RegexParser {
        private let chars: [Character]
        private var index = 0

        private init(_ pattern: String) {
            chars = Array(pattern)
        }

        static func parse(_ pattern: String) throws -> Node {
            guard !pattern.isEmpty else { throw RegexError.empty }
            var parser = RegexParser(pattern)
            let node = try parser.parseAlternation()
            guard parser.isAtEnd else { throw RegexError.unbalanced }
            return node
        }

        private mutating func parseAlternation() throws -> Node {
            var branches = try [parseBranch()]
            while peek() == "|" {
                advance()
                try branches.append(parseBranch())
            }
            return branches.count == 1 ? branches[0] : .alternate(branches)
        }

        private mutating func parseBranch() throws -> Node {
            var pieces: [Node] = []
            while let character = peek(), character != "|", character != ")" {
                try pieces.append(parsePiece())
            }
            if pieces.isEmpty { return .empty }
            return pieces.count == 1 ? pieces[0] : .concat(pieces)
        }

        private mutating func parsePiece() throws -> Node {
            if let character = peek(), "?*+".contains(character) || character == "{" {
                throw RegexError.danglingQuantifier
            }
            let atom = try parseAtom()
            return try applyQuantifier(to: atom)
        }

        private mutating func applyQuantifier(to atom: Node) throws -> Node {
            switch peek() {
            case "?": advance()
                return .repeated(atom, min: 0, max: 1)
            case "*": advance()
                return .repeated(atom, min: 0, max: nil)
            case "+": advance()
                return .repeated(atom, min: 1, max: nil)
            case "{": return try parseBoundedQuantifier(atom)
            default: return atom
            }
        }

        private mutating func parseBoundedQuantifier(_ atom: Node) throws -> Node {
            advance()
            let minimum = parseInteger()
            var maximum: Int? = minimum
            if peek() == "," {
                advance()
                maximum = peek() == "}" ? nil : parseInteger()
            }
            guard peek() == "}", let minimum else { throw RegexError.badQuantifier }
            advance()
            return .repeated(atom, min: minimum, max: maximum)
        }

        private mutating func parseAtom() throws -> Node {
            guard let character = peek() else { throw RegexError.danglingQuantifier }
            switch character {
            case "(":
                advance()
                let inner = try parseAlternation()
                guard peek() == ")" else { throw RegexError.unbalanced }
                advance()
                return inner
            case "[":
                return try .characters(parseClass())
            case ".":
                advance()
                return .characters(.named(.anyButLineBreak))
            case "\\":
                advance()
                return try .characters(parseEscape())
            default:
                advance()
                return .characters(.single(scalar(of: character)))
            }
        }

        // MARK: Escapes

        private mutating func parseEscape() throws -> CharClass {
            guard let character = peek() else { throw RegexError.badEscape("") }
            advance()
            if let single = Self.singleEscape(character) {
                return .single(single)
            }
            if let member = Self.classEscape(character) {
                return classFrom(member)
            }
            if character == "p" || character == "P" {
                return try CharClass(categories: [parseCategory(negated: character == "P")])
            }
            throw RegexError.badEscape(String(character))
        }

        /// Parses the `{name}` of a `\p`/`\P` escape into a category predicate,
        /// rejecting an unknown category or block name.
        private mutating func parseCategory(negated: Bool) throws -> CategoryPredicate {
            guard peek() == "{" else { throw RegexError.badEscape(negated ? "P" : "p") }
            advance()
            var name = ""
            while let character = peek(), character != "}" {
                name.append(character)
                advance()
            }
            guard peek() == "}" else { throw RegexError.badClass }
            advance()
            guard let predicate = CategoryPredicate(name: name, negated: negated) else {
                throw RegexError.unsupported("\\p{\(name)}")
            }
            return predicate
        }

        private func classFrom(_ member: ClassMember) -> CharClass {
            switch member {
            case let .scalar(value): .single(value)
            case let .named(named): CharClass(named: [named])
            case let .negatedNamed(named): CharClass(negatedNamed: [named])
            case let .category(predicate): CharClass(categories: [predicate])
            }
        }

        private static func singleEscape(_ character: Character) -> Unicode.Scalar? {
            switch character {
            case "n": "\n"
            case "r": "\r"
            case "t": "\t"
            case "\\", ".", "|", "-", "^", "?", "*", "+", "{", "}", "(", ")", "[", "]":
                character.unicodeScalars.first
            default: nil
            }
        }

        private static let classEscapes: [Character: ClassMember] = [
            "d": .named(.digit), "D": .negatedNamed(.digit),
            "w": .named(.word), "W": .negatedNamed(.word),
            "s": .named(.space), "S": .negatedNamed(.space),
            "i": .named(.nameStart), "I": .negatedNamed(.nameStart),
            "c": .named(.nameChar), "C": .negatedNamed(.nameChar),
        ]

        private static func classEscape(_ character: Character) -> ClassMember? {
            classEscapes[character]
        }

        // MARK: Character classes

        private mutating func parseClass() throws -> CharClass {
            advance()
            var cls = CharClass()
            if peek() == "^" {
                advance()
                cls.negated = true
            }
            while let character = peek(), character != "]" {
                if character == "-", peek(1) == "[" {
                    advance()
                    cls.subtraction = try [parseClass()]
                    break
                }
                try parseClassMember(into: &cls)
            }
            guard peek() == "]" else { throw RegexError.badClass }
            advance()
            return cls
        }

        private mutating func parseClassMember(into cls: inout CharClass) throws {
            let member = try nextClassMember()
            guard case let .scalar(low) = member else {
                add(member, to: &cls)
                return
            }
            // A "-" immediately before "[" opens a class subtraction (`[abc-[b]]`),
            // not a range, so it is left for parseClass; "-]" is a literal hyphen.
            // Otherwise "-" introduces a range whose endpoints must be ordered: a
            // reversed range like [z-a] is an error, not a trapping `low ... high`.
            if peek() == "-", peek(1) != "]", peek(1) != "[" {
                advance()
                guard case let .scalar(high) = try nextClassMember() else { throw RegexError.badClass }
                guard low <= high else { throw RegexError.badClass }
                cls.ranges.append(low ... high)
            } else {
                cls.ranges.append(low ... low)
            }
        }

        private func add(_ member: ClassMember, to cls: inout CharClass) {
            switch member {
            case let .scalar(value): cls.ranges.append(value ... value)
            case let .named(named): cls.named.append(named)
            case let .negatedNamed(named): cls.negatedNamed.append(named)
            case let .category(predicate): cls.categories.append(predicate)
            }
        }

        private mutating func nextClassMember() throws -> ClassMember {
            guard let character = peek() else { throw RegexError.badClass }
            advance()
            guard character == "\\" else { return .scalar(scalar(of: character)) }
            guard let escaped = peek() else { throw RegexError.badClass }
            advance()
            if let single = Self.singleEscape(escaped) { return .scalar(single) }
            if let member = Self.classEscape(escaped) { return member }
            if escaped == "p" || escaped == "P" {
                return try .category(parseCategory(negated: escaped == "P"))
            }
            throw RegexError.badEscape(String(escaped))
        }

        // MARK: Cursor

        private func scalar(of character: Character) -> Unicode.Scalar {
            character.unicodeScalars.first ?? Unicode.Scalar(0)
        }

        private mutating func parseInteger() -> Int? {
            var digits = ""
            while let character = peek(), character.isNumber {
                digits.append(character)
                advance()
            }
            return Int(digits)
        }

        private var isAtEnd: Bool {
            index >= chars.count
        }

        private func peek(_ ahead: Int = 0) -> Character? {
            let target = index + ahead
            return target < chars.count ? chars[target] : nil
        }

        private mutating func advance() {
            if index < chars.count { index += 1 }
        }
    }
}
