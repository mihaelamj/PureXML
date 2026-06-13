extension PureXML.Regex {
    /// An error compiling a regular expression.
    enum RegexError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case empty
        case unbalanced
        case danglingQuantifier
        case badEscape(String)
        case badClass
        case badQuantifier
        case unsupported(String)

        var description: String {
            switch self {
            case .empty: "the pattern is empty"
            case .unbalanced: "unbalanced parentheses"
            case .danglingQuantifier: "a quantifier has nothing to repeat"
            case let .badEscape(detail): "invalid escape '\\\(detail)'"
            case .badClass: "malformed character class"
            case .badQuantifier: "malformed quantifier"
            case let .unsupported(detail): "unsupported construct: \(detail)"
            }
        }
    }

    /// A named character class (`\d`, `\w`, `\s`, `\i`, `\c`) or the `.` wildcard.
    enum NamedClass: Equatable, Sendable {
        case digit
        case word
        case space
        case nameStart
        case nameChar
        case anyButLineBreak

        func contains(_ scalar: Unicode.Scalar) -> Bool {
            switch self {
            case .digit: scalar.properties.numericType == .decimal
            case .space: scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
            // XSD \w is [#x0000-#x10FFFF]-[\p{P}\p{Z}\p{C}]: everything except
            // punctuation, separators, and other. So symbols and marks are word
            // characters, and `_` (Pc) is not, unlike the Perl definition.
            case .word: !(CategoryMatcher.matches("P", scalar) || CategoryMatcher.matches("Z", scalar) || CategoryMatcher.matches("C", scalar))
            case .nameStart: PureXML.Parsing.XMLCharacter.isNameStart(scalar)
            case .nameChar: PureXML.Parsing.XMLCharacter.isNameChar(scalar)
            case .anyButLineBreak: scalar != "\n" && scalar != "\r"
            }
        }
    }

    /// A character class: ranges, named sub-classes, and an optional negation.
    struct CharClass: Equatable, Sendable {
        var negated = false
        var ranges: [ClosedRange<Unicode.Scalar>] = []
        var named: [NamedClass] = []
        var negatedNamed: [NamedClass] = []
        /// `\p{...}`/`\P{...}` Unicode category and block tests.
        var categories: [CategoryPredicate] = []
        /// A character-class subtraction (`[a-z-[aeiou]]`): characters this class
        /// otherwise admits are removed when the subtrahend matches them. Nests.
        var subtraction: [CharClass] = []

        func matches(_ character: Character) -> Bool {
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
                return false
            }
            var hit = ranges.contains { $0.contains(scalar) }
                || named.contains { $0.contains(scalar) }
                || negatedNamed.contains { !$0.contains(scalar) }
                || categories.contains { $0.contains(scalar) }
            if hit, subtraction.contains(where: { $0.matches(character) }) { hit = false }
            return negated ? !hit : hit
        }

        static func single(_ scalar: Unicode.Scalar) -> CharClass {
            CharClass(ranges: [scalar ... scalar])
        }

        static func named(_ named: NamedClass) -> CharClass {
            CharClass(named: [named])
        }
    }

    /// The parsed regular-expression tree. Groups are non-capturing; `?`, `*`,
    /// `+`, and `{n,m}` all become ``repeated``.
    indirect enum Node: Equatable, Sendable {
        case empty
        case characters(CharClass)
        case concat([Node])
        case alternate([Node])
        case repeated(Node, min: Int, max: Int?)
    }
}
