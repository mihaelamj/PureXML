import Testing
@testable import PureXML

/// An element with a `fixed` value constraint must carry its fixed character value
/// and no element children, even under a mixed content type (cvc-elt.5.2.2.2.1).
/// An empty element takes the fixed value, text equal to the fixed value is fine,
/// but element children make the element invalid.
@Suite("fixed element children")
struct SchemaFixedElementChildrenTests {
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns="u" xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="u">
          <xs:complexType name="CT" mixed="true"><xs:sequence>
            <xs:element name="a" minOccurs="0" type="xs:byte"/>
          </xs:sequence></xs:complexType>
          <xs:element name="e" type="CT" fixed="abc"/>
        </xs:schema>
        """)
    }

    @Test("empty or matching text under a fixed mixed element is accepted")
    func test_emptyOrMatchingTextAccepted() throws {
        #expect(try schema().validate(#"<e xmlns="u"/>"#).isEmpty)
        #expect(try schema().validate(#"<e xmlns="u">abc</e>"#).isEmpty)
    }

    @Test("a fixed mixed element with element children is rejected")
    func test_childrenRejected() throws {
        #expect(try !schema().validate(#"<e xmlns="u">abc<a xmlns="">1</a></e>"#).isEmpty)
        #expect(try !schema().validate(#"<e xmlns="u"><a xmlns="">1</a>abc</e>"#).isEmpty)
    }
}
