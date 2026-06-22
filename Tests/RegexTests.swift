import Testing
@testable import PureXML

@Suite("Regex")
struct RegexTests {
    private func matches(_ pattern: String, _ string: String) throws -> Bool {
        try PureXML.Regex.matches(pattern, string)
    }

    @Test("Literal patterns match the whole string")
    func test_literal() throws {
        #expect(try matches("abc", "abc"))
        #expect(try !matches("abc", "abcd"))
        #expect(try !matches("abc", "ab"))
    }

    @Test("The dot matches any character except line breaks")
    func test_dot() throws {
        #expect(try matches("a.c", "axc"))
        #expect(try !matches("a.c", "a\nc"))
    }

    @Test("Quantifiers ? * + bound repetition")
    func test_quantifiers() throws {
        #expect(try matches("ab?c", "ac"))
        #expect(try matches("ab?c", "abc"))
        #expect(try matches("ab*c", "abbbc"))
        #expect(try matches("ab+c", "abc"))
        #expect(try !matches("ab+c", "ac"))
    }

    @Test("Bounded quantifiers {n}, {n,}, {n,m}")
    func test_boundedQuantifiers() throws {
        #expect(try matches("a{3}", "aaa"))
        #expect(try !matches("a{3}", "aa"))
        #expect(try matches("a{2,}", "aaaa"))
        #expect(try matches("a{2,4}", "aaa"))
        #expect(try !matches("a{2,4}", "aaaaa"))
    }

    @Test("Alternation and grouping")
    func test_alternationGrouping() throws {
        #expect(try matches("cat|dog", "dog"))
        #expect(try matches("(ab)+", "ababab"))
        #expect(try matches("gr(a|e)y", "grey"))
        #expect(try !matches("gr(a|e)y", "groy"))
    }

    @Test("Character classes with ranges and negation")
    func test_charClasses() throws {
        #expect(try matches("[a-z]+", "hello"))
        #expect(try !matches("[a-z]+", "Hello"))
        #expect(try matches("[^0-9]+", "abc"))
        #expect(try matches("[abc]{2}", "ca"))
    }

    @Test("A '-[' opens class subtraction even after a class member")
    func test_classSubtractionAfterMember() throws {
        // `[abcd-[d]]` is {a,b,c,d} minus {d} = {a,b,c}; the `d-[` must read as
        // subtraction, not a `d`..`[` range that traps on reversed bounds (#129,
        // XSTS RegexTest_322).
        #expect(try matches("[abcd-[d]]+", "abcabc"))
        #expect(try !matches("[abcd-[d]]+", "dddaabbccddd"))
        #expect(try matches("[a-z-[aeiou]]+", "bcdfg"))
        #expect(try !matches("[a-z-[aeiou]]+", "bcde"))
    }

    @Test("A reversed range is rejected, not a trap")
    func test_reversedRangeRejected() {
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("[z-a]") }
    }

    @Test("Class escapes \\d \\w \\s and their negations")
    func test_classEscapes() throws {
        #expect(try matches("\\d{4}", "2026"))
        #expect(try !matches("\\d{4}", "20x6"))
        #expect(try matches("\\w+", "abc1"))
        // XSD \w is the complement of \p{P}\p{Z}\p{C}: symbols and marks are word
        // characters, while the connector `_` (Pc) and whitespace are not.
        #expect(try matches("\\w", "+"))
        #expect(try !matches("\\w", "_"))
        #expect(try !matches("\\w", " "))
        #expect(try matches("a\\sb", "a b"))
        #expect(try matches("\\D+", "abc"))
        // XSTS reT51: Tamil digit U+0BE6 was unassigned in Unicode 3.1, so it matches \D.
        #expect(try matches("\\D", "\u{0BE6}"))
        // XSTS reZ003v: ceiling brackets were Sm in Unicode 3.1, so they match `\w`.
        #expect(try matches("\\w", "\u{2308}"))
        #expect(try matches("[\\w]", "\u{2308}"))
        #expect(try matches("[\\w]", "\u{2309}"))
        // XSTS reZ004v: decimal digits from other scripts match `\d` via Nd.
        #expect(try matches("\\d", "\u{0661}"))
    }

    @Test("Escaped metacharacters are literal")
    func test_escapes() throws {
        #expect(try matches("a\\.b", "a.b"))
        #expect(try !matches("a\\.b", "axb"))
        #expect(try matches("\\(\\)", "()"))
    }

    @Test("A realistic ISBN-like pattern")
    func test_realistic() throws {
        let pattern = "\\d{3}-\\d{1,5}-\\d{1,7}-\\d{1,6}-[0-9X]"
        #expect(try matches(pattern, "978-0-13-468599-1"))
        #expect(try !matches(pattern, "abc-0-13-468599-1"))
    }

    @Test("Malformed patterns are rejected")
    func test_errors() {
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("a(b") }
        #expect(throws: PureXML.Regex.RegexError.self) { _ = try PureXML.Regex.Pattern("*ab") }
    }

    @Test("An incomplete trailing escape is rejected")
    func test_incompleteEscape() throws {
        // A `\` with nothing after it is never a valid XSD pattern.
        #expect(throws: PureXML.Regex.RegexError.incompleteEscape) { _ = try PureXML.Regex.Pattern("a\\") }
        #expect(throws: PureXML.Regex.RegexError.incompleteEscape) { _ = try PureXML.Regex.Pattern("[a\\") }
        // A completed escape stays valid: `\[` is a literal bracket.
        #expect(try matches("a\\[", "a["))
    }

    @Test("An unterminated character class is rejected")
    func test_unterminatedClass() throws {
        // A `[` the expression ends before closing with `]` is invalid.
        #expect(throws: PureXML.Regex.RegexError.unterminatedClass) { _ = try PureXML.Regex.Pattern("a[") }
        #expect(throws: PureXML.Regex.RegexError.unterminatedClass) { _ = try PureXML.Regex.Pattern("[a-") }
        // A closed class, and a class whose only `]` is escaped, stay valid.
        #expect(try matches("[abc]", "b"))
        #expect(try matches("[a\\]]", "]"))
    }

    @Test("An unescaped '[' inside a character class is rejected")
    func test_unescapedClassBracket() throws {
        // Per XSD Appendix F a literal `[` inside a class must be escaped (`\[`);
        // a nested class is legal only as a `-[...]` subtraction. The XSTS cases
        // RegexTest_993 / RegexTest_1477 declare the pattern `[a[:xyz:]`, an
        // unescaped inner `[`, so the schema declaring them is invalid.
        #expect(throws: PureXML.Regex.RegexError.unescapedClassBracket) { _ = try PureXML.Regex.Pattern("[a[:xyz:]") }
        #expect(throws: PureXML.Regex.RegexError.unescapedClassBracket) { _ = try PureXML.Regex.Pattern("[a[bc]") }
        #expect(throws: PureXML.Regex.RegexError.unescapedClassBracket) { _ = try PureXML.Regex.Pattern("[[abc]") }
        // With no closing `]`, the inner `[` still faults first (more precise than
        // the unterminated-class diagnosis the swallowed `[` used to produce).
        #expect(throws: PureXML.Regex.RegexError.unescapedClassBracket) { _ = try PureXML.Regex.Pattern("[a[:xyz:") }
        // An escaped `[` and a `-[...]` subtraction stay valid.
        #expect(try matches("[a\\[c]", "["))
        #expect(try matches("[a-z-[aeiou]]", "b"))
        #expect(try !matches("[a-z-[aeiou]]", "e"))
    }

    @Test("The empty pattern is valid and matches only the empty string")
    func test_emptyPattern() throws {
        // XSD grammar (Datatypes Appendix F): branch ::= piece*, so a branch
        // may have zero pieces. The empty regex is valid and matches "".
        #expect(try matches("", ""))
        #expect(try !matches("", "a"))
    }

    @Test("Pathological quantifiers compile bounded instead of exhausting memory")
    func test_quantifierExplosionBounded() throws {
        // `a{1000000000}` would unroll a billion automaton states without a
        // ceiling; the nested form multiplies. Both must build and answer
        // without the OOM that killed the XSTS msMeta Regex set (#129).
        _ = try matches("a{1000000000}", String(repeating: "a", count: 64))
        _ = try matches("(a{100000}){100000}", "aaaa")
        // Ordinary bounded quantifiers keep their exact semantics.
        #expect(try matches("a{2,4}", "aaa"))
        #expect(try !matches("a{2,4}", "a"))
        #expect(try !matches("a{2,4}", "aaaaa"))
    }

    @Test("Unicode block escapes match within their block and reject outside it")
    func test_unicodeBlocks() throws {
        // \u{0531} Armenian, \u{0B85} Tamil, \u{1100} Hangul Jamo.
        #expect(try matches(#"\p{IsArmenian}+"#, "\u{0531}\u{0561}"))
        #expect(try !matches(#"\p{IsArmenian}+"#, "abc"))
        #expect(try matches(#"\p{IsTamil}+"#, "\u{0B85}"))
        #expect(try matches(#"\p{IsHangulJamo}+"#, "\u{1100}"))
        #expect(try !matches(#"\p{IsTamil}+"#, "\u{0531}")) // Armenian is not Tamil
        // An unknown block name is a compile error (the block set is complete, so
        // an unrecognised name is a genuine syntax error, not an engine limitation).
        #expect(throws: PureXML.Regex.RegexError.invalidProperty) { _ = try PureXML.Regex.Pattern(#"\p{IsNotARealBlock}"#) }
    }
}
