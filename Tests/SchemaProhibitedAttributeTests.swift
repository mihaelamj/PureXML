import Testing
@testable import PureXML

/// `use="prohibited"` excludes an attribute from a complex type's effective
/// {attribute uses} (XSD 1.0 §3.4.2): the attribute is then undeclared, so its
/// presence is rejected when no wildcard admits it, but is still admitted (and
/// validated per `processContents`) when an attribute wildcard covers it. The
/// prohibited declaration is kept for schema-validity checks, not dropped.
@Suite("prohibited attribute use")
struct SchemaProhibitedAttributeTests {
    @Test("a prohibited attribute with no wildcard is rejected when present")
    func test_prohibitedNoWildcardRejected() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="e"><xs:complexType>
            <xs:attribute name="gone" use="prohibited" type="xs:string"/>
            <xs:attribute name="ok" type="xs:string"/>
          </xs:complexType></xs:element>
        </xs:schema>
        """)
        #expect(try !schema.validate(#"<e gone="y"/>"#).isEmpty)
        // Omitting the prohibited attribute, with the allowed one, is valid.
        #expect(try schema.validate(#"<e ok="x"/>"#).isEmpty)
    }

    /// The W3C attZ002 shape: a prohibited attribute is still admitted by a lax
    /// `anyAttribute` wildcard, so the instance is valid (the prohibition removes
    /// the use, the wildcard independently admits the name).
    @Test("a prohibited attribute admitted by a wildcard is accepted")
    func test_prohibitedAdmittedByWildcardAccepted() throws {
        let schema = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" attributeFormDefault="unqualified">
          <xs:element name="root"><xs:complexType>
            <xs:attribute name="attr" use="prohibited"/>
            <xs:anyAttribute namespace="##local" processContents="lax"/>
          </xs:complexType></xs:element>
        </xs:schema>
        """)
        #expect(try schema.validate(#"<root attr="123"/>"#).isEmpty)
    }
}
