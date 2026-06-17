extension PureXML.Regex {
    /// An error compiling a regular expression.
    enum RegexError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case unbalanced
        case danglingQuantifier
        case badEscape(String)
        case badClass
        case badQuantifier
        case unsupported(String)
        /// A character-class range whose first endpoint exceeds its second
        /// (`[b-a]`): unambiguously invalid, never an engine limitation.
        case reversedRange
        /// An empty character class (`[]`): a class requires at least one member.
        case emptyClass
        /// A bounded quantifier whose minimum exceeds its maximum (`{37,17}`).
        case reversedQuantifier
        /// A `\` with no following character (`a\`): an escape was opened but the
        /// expression ended. Unambiguously invalid, never an engine limitation.
        case incompleteEscape
        /// A character class opened with `[` that the expression ends before
        /// closing with `]` (`a[`, `[a[:xyz:`). Unambiguously invalid.
        case unterminatedClass
        /// The `{...}` of a `\p`/`\P` escape whose content can be no XSD charProp:
        /// empty, the bare prefix `Is`, a non-block name carrying a character that
        /// is not a letter, or `Is` followed by a non-block-name character
        /// (`\p{\L}`, `\p{Is}`). Unambiguously invalid, distinct from an unknown but
        /// well-formed category or block name (which stays an `unsupported` limit).
        case invalidProperty

        var description: String {
            switch self {
            case .unbalanced: "unbalanced parentheses"
            case .danglingQuantifier: "a quantifier has nothing to repeat"
            case let .badEscape(detail): "invalid escape '\\\(detail)'"
            case .badClass: "malformed character class"
            case .badQuantifier: "malformed quantifier"
            case let .unsupported(detail): "unsupported construct: \(detail)"
            case .reversedRange: "character-class range is reversed"
            case .emptyClass: "empty character class"
            case .reversedQuantifier: "quantifier minimum exceeds maximum"
            case .incompleteEscape: "an escape '\\' has no following character"
            case .unterminatedClass: "a character class is not closed with ']'"
            case .invalidProperty: "a \\p{...} property name is malformed"
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
            case .digit: return XSDCategory.generalCategoryCode(scalar) == "Nd"
            case .space: return scalar == " " || scalar == "\t" || scalar == "\n" || scalar == "\r"
            // XSD \w is [#x0000-#x10FFFF]-[\p{P}\p{Z}\p{C}] (Datatypes Appendix F).
            // Symbols and marks are word characters; `_` (Pc) is not, unlike the
            // Perl definition.
            case .word:
                let code = XSDCategory.generalCategoryCode(scalar)
                return !(code.hasPrefix("P") || code.hasPrefix("Z") || code.hasPrefix("C"))
            case .nameStart: return PureXML.Parsing.XMLCharacter.isNameStart(scalar)
            case .nameChar: return PureXML.Parsing.XMLCharacter.isNameChar(scalar)
            case .anyButLineBreak: return scalar != "\n" && scalar != "\r"
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
            return matches(scalar)
        }

        func matches(_ scalar: Unicode.Scalar) -> Bool {
            var hit = ranges.contains { $0.contains(scalar) }
                || named.contains { $0.contains(scalar) }
                || negatedNamed.contains { !$0.contains(scalar) }
                || categories.contains { $0.contains(scalar) }
            if hit, subtraction.contains(where: { $0.matches(scalar) }) { hit = false }
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
