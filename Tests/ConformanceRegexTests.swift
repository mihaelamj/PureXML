import Testing
@testable import PureXML

/// XSD regex (`xs:pattern`) conformance, driven through the validation
/// framework (Tier 2): the XML Schema regex flavor against its spec semantics,
/// exercised end to end through pattern-facet validation.
@Suite("Conformance corpus: XSD regex patterns")
struct ConformanceRegexTests {
    private struct PatternSpec {
        let name: String
        let pattern: String
        let value: String
        let valid: Bool
    }

    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            // Whole-string anchoring is implicit in the XSD flavor.
            PatternSpec(name: "implicit-anchoring", pattern: "abc", value: "xabcx", valid: false),
            PatternSpec(name: "exact-match", pattern: "abc", value: "abc", valid: true),
            // Character-class escapes.
            PatternSpec(name: "digits-ok", pattern: "\\d{3}", value: "123", valid: true),
            PatternSpec(name: "digits-fail", pattern: "\\d{3}", value: "12a", valid: false),
            // XSD \w excludes punctuation, so the connector `_` (Pc) is not a word char.
            PatternSpec(name: "word-chars", pattern: "\\w+", value: "abc1", valid: true),
            PatternSpec(name: "word-chars-no-underscore", pattern: "\\w", value: "_", valid: false),
            PatternSpec(name: "whitespace-escape", pattern: "a\\sb", value: "a b", valid: true),
            // Unicode categories and blocks.
            PatternSpec(name: "category-letters", pattern: "\\p{L}+", value: "abcé", valid: true),
            PatternSpec(name: "category-rejects-digit", pattern: "\\p{L}+", value: "ab1", valid: false),
            PatternSpec(name: "negated-category", pattern: "\\P{Nd}+", value: "abc", valid: true),
            // Quantifier ranges.
            PatternSpec(name: "range-min-ok", pattern: "a{2,3}", value: "aa", valid: true),
            PatternSpec(name: "range-over-max", pattern: "a{2,3}", value: "aaaa", valid: false),
            PatternSpec(name: "open-range", pattern: "a{2,}", value: "aaaaa", valid: true),
            // Alternation, grouping, class negation, subtraction.
            PatternSpec(name: "alternation", pattern: "(cat|dog)", value: "dog", valid: true),
            PatternSpec(name: "negated-class", pattern: "[^0-9]+", value: "abc", valid: true),
            PatternSpec(name: "negated-class-fail", pattern: "[^0-9]+", value: "a1c", valid: false),
            PatternSpec(name: "class-subtraction", pattern: "[a-z-[aeiou]]+", value: "bcd", valid: true),
            PatternSpec(name: "class-subtraction-fail", pattern: "[a-z-[aeiou]]+", value: "bad", valid: false),
        ]
        return try specs.map { spec in
            let xsd = """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="v"><xs:simpleType><xs:restriction base="xs:string"><xs:pattern value="\(spec.pattern)"/></xs:restriction></xs:simpleType></xs:element>
            </xs:schema>
            """
            let errors = try PureXML.Schema.Document(xsd).validate("<v>\(spec.value)</v>")
            return PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: errors.isEmpty ? "valid" : "invalid",
                expected: spec.valid ? "valid" : "invalid",
            )
        }
    }

    @Test("The XSD regex conformance corpus passes with no located failures")
    func test_regexCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
