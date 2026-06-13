@testable import PureXML
import Testing

/// A `pattern` facet value must be a valid XSD regular expression. The pattern
/// was only compiled lazily at instance time (`try?`), so an unparseable one was
/// silently ignored and the schema accepted. Compile-time validation rejects the
/// unambiguous structural errors (unbalanced parentheses, a quantifier with
/// nothing to repeat) while tolerating constructs the engine merely does not
/// support on an otherwise-valid pattern (an untabulated `\p{Is...}` block, the
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

    @Test("a construct the engine does not support is not treated as a schema error")
    func test_engineGapTolerated() throws {
        // Empty pattern (valid: matches the empty string), an untabulated Unicode
        // block escape, and the lenient `{,m}` quantifier are all accepted.
        try compile("")
        try compile(#"\p{IsHighSurrogates}"#)
        try compile("[0-9]{,5}")
    }
}
