import Testing
@testable import PureXML

/// `pattern` and `enumeration` are the only constraining facets XSD allows on a
/// union, and both must be enforced on top of member-type membership (#147).
/// They had been ignored, so any value valid for a member slipped through.
@Suite("Union restriction facets")
struct SchemaUnionFacetTests {
    private func schema(_ facets: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="intOrName">
            <xs:union memberTypes="xs:int xs:string"/>
          </xs:simpleType>
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="intOrName">\(facets)</xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("Enumeration on a union restricts to the listed values")
    func test_enumeration() throws {
        let doc = try schema(#"<xs:enumeration value="5"/><xs:enumeration value="foo"/>"#)
        #expect(try doc.validate("<v>5</v>").isEmpty) // listed
        #expect(try doc.validate("<v>foo</v>").isEmpty) // listed
        #expect(try !doc.validate("<v>7</v>").isEmpty) // valid int, not listed
        #expect(try !doc.validate("<v>bar</v>").isEmpty) // valid string, not listed
    }

    @Test("Union enumeration compares in value space, not lexically")
    func test_enumerationValueSpace() throws {
        let doc = try schema(#"<xs:enumeration value="5"/>"#)
        // 05 is a valid xs:int equal to the enumerated 5, so it is in the set.
        #expect(try doc.validate("<v>05</v>").isEmpty)
    }

    @Test("Pattern on a union constrains the lexical value")
    func test_pattern() throws {
        let doc = try schema(#"<xs:pattern value="[a-z]+"/>"#)
        #expect(try doc.validate("<v>abc</v>").isEmpty) // valid string, matches
        #expect(try !doc.validate("<v>5</v>").isEmpty) // valid int, fails pattern
    }

    @Test("A union with no facets still admits any member value")
    func test_noFacets() throws {
        let doc = try schema("")
        #expect(try doc.validate("<v>42</v>").isEmpty)
        #expect(try doc.validate("<v>anything</v>").isEmpty)
    }
}
