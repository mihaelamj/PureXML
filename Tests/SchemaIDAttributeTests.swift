@testable import PureXML
import Testing

/// The `id` attribute on any XSD component is of type `xs:ID`: its value must be
/// a valid NCName and unique within the schema document (XSD Structures). Such a
/// schema is invalid and must be rejected at compile time; previously the `id`
/// value was never checked and the schema accepted (XSTS invalid-schema idA-idK,
/// attgA, attB, ctA, and related cases).
@Suite("Schema id attribute validity")
struct SchemaIDAttributeTests {
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

    @Test("valid, unique id attributes compile")
    func test_valid() throws {
        try compile(#"<xs:element name="a" id="anId"/><xs:element name="b" id="_other-1"/>"#)
        try compile(#"""
        <xs:element name="root">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:unique id="u1" name="uq"><xs:selector xpath="a"/><xs:field xpath="@k"/></xs:unique>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="k" type="xs:string"/></xs:complexType></xs:element>
        """#)
    }

    @Test("an id value that is not a valid NCName is rejected")
    func test_idNotNCName() {
        #expect(rejects(#"<xs:element name="a" id=""/>"#))
        #expect(rejects(#"<xs:element name="a" id="123"/>"#))
        #expect(rejects(#"<xs:element name="a" id="a b"/>"#))
        #expect(rejects(#"<xs:element name="a" id="pre:fix"/>"#))
    }

    @Test("a duplicated id value in the schema document is rejected")
    func test_duplicateId() {
        #expect(rejects(#"<xs:element name="a" id="dup"/><xs:element name="b" id="dup"/>"#))
        // A duplicate across different component kinds (element and a constraint).
        #expect(rejects(#"""
        <xs:element name="root" id="dup">
          <xs:complexType><xs:sequence><xs:element ref="a"/></xs:sequence></xs:complexType>
          <xs:unique id="dup" name="uq"><xs:selector xpath="a"/><xs:field xpath="@k"/></xs:unique>
        </xs:element>
        <xs:element name="a"><xs:complexType><xs:attribute name="k" type="xs:string"/></xs:complexType></xs:element>
        """#))
    }

    @Test("foreign id attributes are not treated as xs:ID")
    func test_foreignIdsIgnored() throws {
        // Foreign content inside xs:documentation carries its own non-xs:ID `id`
        // attributes; repeated or non-NCName values there must not reject the schema.
        try compile(#"""
        <xs:element name="a">
          <xs:annotation><xs:documentation><html:p xmlns:html="http://www.w3.org/1999/xhtml" id="content"/></xs:documentation></xs:annotation>
        </xs:element>
        <xs:element name="b">
          <xs:annotation><xs:documentation><html:p xmlns:html="http://www.w3.org/1999/xhtml" id="content"/></xs:documentation></xs:annotation>
        </xs:element>
        """#)
        // A prefixed xml:id is a different attribute, not the schema-component id.
        try compile(#"<xs:element name="a" xml:id="123"/>"#)
    }

    @Test("the rejection message names the id problem")
    func test_message() {
        do {
            try compile(#"<xs:element name="a" id="123"/>"#)
            Issue.record("expected a malformed id to be rejected")
        } catch {
            #expect(String(describing: error).contains("id attribute"))
        }
    }
}
