extension PureXML.Regex {
    /// An error compiling a regular expression.
    enum RegexError: Swift.Error, Equatable, Sendable, CustomStringConvertible {
        case unbalanced
        case danglingQuantifier
        case badEscape(String)
        case badClass
        case badQuantifier
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
        /// closing with `]` (`a[`). Unambiguously invalid.
        case unterminatedClass
        /// An unescaped `[` inside a character class (`[a[bc]`, `[a[:xyz:]`): XSD
        /// Appendix F `SingleCharNoEsc` excludes `[`, and a nested class is legal
        /// only as a `-[...]` subtraction, so a `[` not introduced by `-` is a
        /// syntax error. Unambiguously invalid per the grammar, never an engine
        /// limitation.
        ///
        /// Contested-corpus note: this rejects not only the W3C-*settled* invalid
        /// cases (XSTS RegexTest_993/1477, `[a[:xyz:]`) but also siblings the MS
        /// suite marks *valid* (`([[:]+)`, `([[=]+)`, `([[.]+)`, RegexTest_989/990/
        /// 991/1473-1475, and the space-bearing subtraction `[a - c - [ b ] ]+`,
        /// 479/480). Those entries are W3C-*queried* (status="queried", Bugzilla
        /// #4118) precisely because "valid" contradicts the Appendix F grammar; the
        /// suite's settled position (993/1477) agrees with rejecting. PureXML
        /// follows the grammar, which is also the W3C's settled direction. The
        /// queried siblings are excluded from the XSTS conformance gate, so this
        /// is not a counted false positive. A deliberate spec-strict choice, not an
        /// oversight.
        case unescapedClassBracket
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
            case .reversedRange: "character-class range is reversed"
            case .emptyClass: "empty character class"
            case .reversedQuantifier: "quantifier minimum exceeds maximum"
            case .incompleteEscape: "an escape '\\' has no following character"
            case .unterminatedClass: "a character class is not closed with ']'"
            case .unescapedClassBracket: "an unescaped '[' inside a character class"
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
            let inBase = ranges.contains { $0.contains(scalar) }
                || named.contains { $0.contains(scalar) }
                || negatedNamed.contains { !$0.contains(scalar) }
                || categories.contains { $0.contains(scalar) }
            // XSD `charClassSub ::= (posCharGroup | negCharGroup) '-' charClassExpr`
            // is the set difference of the (possibly NEGATED) group and the
            // subtrahend, so negation applies to the base FIRST, then subtraction
            // removes from that result: `[^cde-[ag]]` is (not c/d/e) minus a/g,
            // i.e. excludes {a,c,d,e,g}, not just {c,d,e} (XSTS RegexTest_430).
            var hit = negated ? !inBase : inBase
            if hit, subtraction.contains(where: { $0.matches(scalar) }) { hit = false }
            return hit
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
