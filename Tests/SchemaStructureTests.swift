@testable import PureXML
import Testing

/// Structural validity of a schema document against the schema-for-schemas
/// content model (XSD 1.0 Structures): each component's children must be
/// admitted by the model, an `annotation` (where allowed once) must be first,
/// and an identity constraint needs a selector and field. Such a schema is
/// invalid and must be rejected at compile time; the children were previously
/// unchecked and the schema accepted (XSTS invalid-schema ctB/ctG/ctH, etc.).
@Suite("Schema structural validity")
struct SchemaStructureTests {
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

    @Test("well-formed components compile")
    func test_valid() throws {
        try compile(#"""
        <xs:complexType name="t">
          <xs:annotation><xs:documentation>doc</xs:documentation></xs:annotation>
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:attribute name="x" type="xs:string"/>
        </xs:complexType>
        """#)
        try compile(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/><xs:field xpath="@id"/></xs:key>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element>
        """#)
    }

    @Test("a child not admitted by the content model is rejected")
    func test_disallowedChild() {
        // element is not a direct child of complexType (it must sit in a group).
        #expect(rejects(#"<xs:complexType name="t"><xs:element name="a" type="xs:string"/></xs:complexType>"#))
        // attribute admits only annotation and simpleType, not sequence.
        #expect(rejects(#"<xs:attribute name="a"><xs:sequence/></xs:attribute>"#))
    }

    @Test("at most one annotation, and it must be first")
    func test_annotationPlacement() {
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:annotation><xs:documentation>one</xs:documentation></xs:annotation>
          <xs:annotation><xs:documentation>two</xs:documentation></xs:annotation>
        </xs:complexType>
        """#))
        #expect(rejects(#"""
        <xs:complexType name="t">
          <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          <xs:annotation><xs:documentation>late</xs:documentation></xs:annotation>
        </xs:complexType>
        """#))
    }

    @Test("schema and redefine may carry several annotations")
    func test_multipleAnnotationOnSchema() throws {
        try compile(#"""
        <xs:annotation><xs:documentation>one</xs:documentation></xs:annotation>
        <xs:element name="a" type="xs:string"/>
        <xs:annotation><xs:documentation>two</xs:documentation></xs:annotation>
        """#)
    }

    @Test("enumerated attributes accept only their value space")
    func test_enumeratedAttributeValues() {
        #expect(rejects(#"<xs:attribute name="a" type="xs:string" use="foo"/>"#))
        #expect(rejects(#"<xs:attribute name="a" type="xs:string" use=""/>"#))
        #expect(rejects(#"<xs:complexType name="t" mixed="yes"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t" abstract="maybe"><xs:sequence/></xs:complexType>"#))
        #expect(rejects(#"<xs:element name="a" type="xs:string" form="Qualified"/>"#))
    }

    @Test("minOccurs and maxOccurs must be nonNegativeInteger (maxOccurs also unbounded)")
    func test_occursValues() throws {
        try compile(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="0" maxOccurs="unbounded"/></xs:sequence></xs:complexType>"#)
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="-1"/></xs:sequence></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" maxOccurs="lots"/></xs:sequence></xs:complexType>"#))
        #expect(rejects(#"<xs:complexType name="t"><xs:sequence><xs:element name="a" type="xs:string" minOccurs="x"/></xs:sequence></xs:complexType>"#))
    }

    @Test("valid enumerated and occurrence attribute values compile")
    func test_validAttributeValues() throws {
        try compile(#"<xs:attribute name="a" type="xs:string" use="required"/>"#)
        try compile(#"<xs:complexType name="t" mixed="true"><xs:sequence/></xs:complexType>"#)
        try compile(#"<xs:complexType name="t" abstract="false"><xs:sequence/></xs:complexType>"#)
    }

    @Test("an identity constraint requires a selector and field")
    func test_identityConstraintRequiresParts() {
        #expect(rejects(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:key name="k"><xs:selector xpath="a"/></xs:key>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element>
        """#))
    }
}
