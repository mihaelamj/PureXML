@testable import PureXML
import Testing

/// Schema-validity of constraining-facet definitions (XSD Part 2 Datatypes 4.3):
/// a length-family facet value must be a valid `nonNegativeInteger`
/// (`totalDigits` a `positiveInteger`), `length` may not co-occur with
/// `minLength`/`maxLength`, and the integer ranges must be ordered. Such a schema
/// is invalid and must be rejected at compile time; previously the malformed
/// value was silently dropped and the schema accepted (XSTS invalid-schema
/// MS DataTypes facet cases).
@Suite("Facet definition validity")
struct SchemaFacetDefinitionTests {
    private func compile(_ facets: String, base: String = "xs:string") throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="\(base)">\(facets)</xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    private func rejects(_ facets: String, base: String = "xs:string") -> Bool {
        do { try compile(facets, base: base)
            return false
        } catch { return true }
    }

    @Test("a well-formed facet definition compiles")
    func test_valid() throws {
        try compile(#"<xs:length value="5"/>"#)
        try compile(#"<xs:minLength value="1"/><xs:maxLength value="10"/>"#)
        try compile(#"<xs:length value="0"/>"#)
        try compile(#"<xs:totalDigits value="3"/><xs:fractionDigits value="2"/>"#, base: "xs:decimal")
        try compile(#"<xs:minLength value="2"/><xs:maxLength value="2"/>"#)
        // A well-formed nonNegativeInteger is accepted regardless of machine-integer
        // range, and tolerates a leading "+" and leading zeros.
        try compile(#"<xs:length value="+5"/>"#)
        try compile(#"<xs:length value="007"/>"#)
        try compile(#"<xs:length value="999999999999999999999999999999"/>"#)
        try compile(#"<xs:minLength value="2"/><xs:maxLength value="99999999999999999999"/>"#)
    }

    @Test("a malformed length-family lexical is rejected")
    func test_malformedLexical() {
        #expect(rejects(#"<xs:length value=""/>"#))
        #expect(rejects(#"<xs:length value="-1"/>"#))
        #expect(rejects(#"<xs:length value="a"/>"#))
        #expect(rejects(#"<xs:length value="1e2"/>"#))
        #expect(rejects(#"<xs:minLength value="x"/>"#))
        #expect(rejects(#"<xs:maxLength value="-5"/>"#))
    }

    @Test("totalDigits must be a positiveInteger")
    func test_totalDigitsPositive() {
        #expect(rejects(#"<xs:totalDigits value="0"/>"#, base: "xs:decimal"))
        #expect(rejects(#"<xs:totalDigits value="-1"/>"#, base: "xs:decimal"))
    }

    @Test("length may not co-occur with minLength or maxLength")
    func test_lengthCoOccurrence() {
        #expect(rejects(#"<xs:length value="5"/><xs:minLength value="1"/>"#))
        #expect(rejects(#"<xs:length value="5"/><xs:maxLength value="10"/>"#))
    }

    @Test("integer facet ranges must be ordered")
    func test_rangeOrder() {
        #expect(rejects(#"<xs:minLength value="10"/><xs:maxLength value="1"/>"#))
        #expect(rejects(#"<xs:totalDigits value="2"/><xs:fractionDigits value="5"/>"#, base: "xs:decimal"))
    }

    @Test("a value-bound facet value must be valid for the base type")
    func test_boundValueValidity() throws {
        try compile(#"<xs:maxInclusive value="5.55"/>"#, base: "xs:decimal")
        try compile(#"<xs:minInclusive value="1"/><xs:maxInclusive value="10"/>"#, base: "xs:decimal")
        #expect(rejects(#"<xs:maxInclusive value=""/>"#, base: "xs:decimal"))
        #expect(rejects(#"<xs:minInclusive value="abc"/>"#, base: "xs:decimal"))
        #expect(rejects(#"<xs:maxExclusive value="1.2.3"/>"#, base: "xs:decimal"))
    }

    @Test("an enumeration value must be valid for the base type")
    func test_enumerationValueValidity() throws {
        try compile(#"<xs:enumeration value="3.5"/>"#, base: "xs:decimal")
        #expect(rejects(#"<xs:enumeration value=""/>"#, base: "xs:float"))
        #expect(rejects(#"<xs:enumeration value="x"/>"#, base: "xs:decimal"))
    }

    @Test("inclusive and exclusive bounds on the same side may not co-occur")
    func test_boundMutualExclusion() {
        #expect(rejects(#"<xs:maxInclusive value="5.55"/><xs:maxExclusive value="5.55"/>"#, base: "xs:decimal"))
        #expect(rejects(#"<xs:minInclusive value="1"/><xs:minExclusive value="1"/>"#, base: "xs:decimal"))
    }

    @Test("the lower bound may not exceed (or, if exclusive, equal) the upper bound")
    func test_boundOrder() {
        #expect(rejects(#"<xs:minInclusive value="7.7"/><xs:maxInclusive value="1.1"/>"#, base: "xs:decimal"))
        #expect(rejects(#"<xs:minExclusive value="5"/><xs:maxExclusive value="5"/>"#, base: "xs:decimal"))
        // An inclusive single-point range is valid.
        do { try compile(#"<xs:minInclusive value="5"/><xs:maxInclusive value="5"/>"#, base: "xs:decimal") } catch {
            Issue.record("a single-point inclusive range must be valid: \(error)")
        }
    }

    @Test("the rejection message names the offending facet")
    func test_locatedMessage() {
        do {
            try compile(#"<xs:length value="a"/>"#)
            Issue.record("expected the malformed facet to be rejected")
        } catch {
            #expect(String(describing: error).contains("length"))
        }
    }
}
