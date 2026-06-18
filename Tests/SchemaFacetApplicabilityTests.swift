import Testing
@testable import PureXML

/// Facet applicability to a simple type's variety (XSD 1.0 Part 2, 4.3): a `list`
/// admits only the length-family, `pattern`, `enumeration`, `whiteSpace`; a `union`
/// only `pattern`/`enumeration`. A value-bound facet on a list or union is invalid
/// (the stF families). An atomic, unresolvable, or external base is left alone.
@Suite("Facet applicability to variety")
struct SchemaFacetApplicabilityTests {
    private func compile(_ body: String) throws {
        _ = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
        \(body)
        </xs:schema>
        """)
    }

    private func rejects(_ body: String) -> Bool {
        do { try compile(body)
            return false
        } catch { return true }
    }

    @Test("a value-bound facet on a list-derived type is rejected")
    func test_listValueBoundFacet() {
        for facet in ["maxInclusive", "maxExclusive", "minInclusive", "minExclusive", "totalDigits", "fractionDigits"] {
            #expect(rejects(#"""
            <xs:simpleType name="l"><xs:list itemType="xs:integer"/></xs:simpleType>
            <xs:simpleType name="t"><xs:restriction base="l"><xs:\#(facet) value="5"/></xs:restriction></xs:simpleType>
            """#), "expected rejection of \(facet) on a list")
        }
        // A built-in list datatype (xs:NMTOKENS) is also a list.
        #expect(rejects(#"<xs:simpleType name="t"><xs:restriction base="xs:NMTOKENS"><xs:maxLength value="3"/><xs:maxInclusive value="5"/></xs:restriction></xs:simpleType>"#))
    }

    @Test("length-family, pattern, enumeration, whiteSpace apply to a list")
    func test_listAllowedFacets() throws {
        try compile(#"""
        <xs:simpleType name="l"><xs:list itemType="xs:integer"/></xs:simpleType>
        <xs:simpleType name="t"><xs:restriction base="l">
          <xs:minLength value="1"/><xs:maxLength value="9"/><xs:enumeration value="1 2 3"/>
        </xs:restriction></xs:simpleType>
        """#)
    }

    @Test("only pattern and enumeration apply to a union")
    func test_unionFacets() throws {
        #expect(rejects(#"""
        <xs:simpleType name="u"><xs:union memberTypes="xs:integer xs:string"/></xs:simpleType>
        <xs:simpleType name="t"><xs:restriction base="u"><xs:maxLength value="3"/></xs:restriction></xs:simpleType>
        """#))
        try compile(#"""
        <xs:simpleType name="u"><xs:union memberTypes="xs:integer xs:string"/></xs:simpleType>
        <xs:simpleType name="t"><xs:restriction base="u"><xs:pattern value="\d+"/><xs:enumeration value="1"/></xs:restriction></xs:simpleType>
        """#)
    }

    @Test("a value-bound facet on an atomic type is left alone")
    func test_atomicUnaffected() throws {
        try compile(#"<xs:simpleType name="t"><xs:restriction base="xs:integer"><xs:maxInclusive value="5"/></xs:restriction></xs:simpleType>"#)
    }

    @Test("variety resolution is namespace-aware: a same-named user type does not shadow a built-in")
    func test_namespaceAwareResolution() throws {
        // A user `simpleType` named `integer` (a list) must not be mistaken for the
        // built-in `xs:integer` when it is the restriction base; the value-bound
        // facet on the atomic built-in is valid.
        try compile(#"""
        <xs:simpleType name="integer"><xs:list itemType="xs:string"/></xs:simpleType>
        <xs:simpleType name="t"><xs:restriction base="xs:integer"><xs:maxInclusive value="5"/></xs:restriction></xs:simpleType>
        """#)
    }
}
