import Testing
@testable import PureXML

/// A `pattern` facet value must be a valid XSD regular expression. The pattern
/// was only compiled lazily at instance time (`try?`), so an unparseable one was
/// silently ignored and the schema accepted. Compile-time validation rejects the
/// unambiguous structural errors (unbalanced parentheses, a quantifier with
/// nothing to repeat, an unknown `\p{...}` category or block name) while tolerating
/// constructs the engine merely under-supports on an otherwise-valid pattern (the
/// empty pattern, the lenient `{,m}` quantifier), so no valid schema is rejected.
@Suite("Pattern facet regex validity")
struct SchemaPatternFacetTests {
    private func compile(_ pattern: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="xs:string"><xs:pattern value="\(pattern)"/></xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    private func rejects(_ pattern: String) -> Bool {
        do { try compile(pattern)
            return false
        } catch { return true }
    }

    @Test("a structurally malformed pattern is rejected")
    func test_malformed() {
        #expect(rejects("((a)"))
        #expect(rejects("(a))"))
        #expect(rejects("?a"))
        #expect(rejects("*a"))
        #expect(rejects("+a"))
    }

    @Test("a valid pattern compiles")
    func test_valid() throws {
        try compile("[a-z]+")
        try compile("[0-9]{2,4}")
        try compile("(ab)*c?")
    }

    @Test("an unescaped '[' inside a character class is rejected (XSTS RegexTest_993/1477)")
    func test_unescapedClassBracket() {
        // `[a[:xyz:]` (XSTS RegexTest_993 and RegexTest_1477) has an unescaped
        // inner `[`, invalid per XSD Appendix F, so the schema is invalid.
        #expect(rejects("[a[:xyz:]"))
        #expect(rejects("[a[bc]"))
        // The escaped form and a `-[...]` subtraction stay valid patterns.
        #expect(!rejects("[a\\[c]"))
        #expect(!rejects("[a-z-[aeiou]]"))
    }

    @Test("a construct the engine does not support is not treated as a schema error")
    func test_engineGapTolerated() throws {
        // The empty pattern (valid: matches the empty string) and the lenient
        // `{,m}` quantifier are accepted.
        try compile("")
        try compile("[0-9]{,5}")
    }

    @Test("an unknown \\p{...} category or block name is rejected (XSTS reK88)")
    func test_unknownPropertyRejected() {
        // `\p{IsaA0-a9}` (XSTS reK88) names no Unicode block; the recognised set is
        // the complete XSD 1.0 charProp list, so an unknown name is a syntax error.
        #expect(rejects(#"\p{IsaA0-a9}"#))
        #expect(rejects(#"\p{IsNotARealBlock}"#))
        #expect(rejects(#"\p{Zz}"#))
    }

    @Test("the complete XSD 1.0 block set compiles, including supplementary and surrogate blocks")
    func test_fullBlockSetCompiles() throws {
        // Supplementary-plane blocks (Unicode 3.1) are valid XSD block names.
        try compile(#"\p{IsMusicalSymbols}"#)
        try compile(#"\p{IsOldItalic}"#)
        try compile(#"\p{IsCJKUnifiedIdeographsExtensionB}"#)
        try compile(#"\p{IsTags}"#)
        // Surrogate blocks are valid names whose ranges hold no scalar (match nothing).
        try compile(#"\p{IsHighSurrogates}"#)
        try compile(#"\p{IsLowSurrogates}"#)
    }
}
