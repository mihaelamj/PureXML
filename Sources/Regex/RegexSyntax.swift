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
            case .word: scalar.properties.isAlphabetic || scalar.properties.numericType == .decimal || scalar == "_"
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

        func matches(_ character: Character) -> Bool {
            guard character.unicodeScalars.count == 1, let scalar = character.unicodeScalars.first else {
                return false
            }
            let hit = ranges.contains { $0.contains(scalar) }
                || named.contains { $0.contains(scalar) }
                || negatedNamed.contains { !$0.contains(scalar) }
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

extension Unicode.Scalar: @retroactive Comparable {
    public static func < (lhs: Unicode.Scalar, rhs: Unicode.Scalar) -> Bool {
        lhs.value < rhs.value
    }
}
