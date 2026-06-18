import Testing
@testable import PureXML

/// `length`, `minLength`, and `maxLength` on `xs:QName` do not constrain the
/// value: XSD 1.0 Datatypes 4.3.1 leaves the unit of length unspecified for
/// QName, so (like Xerces and the XSTS NIST oracle) any QName satisfies them
/// (#147). Lexical QName validity is still enforced.
@Suite("QName length facets")
struct SchemaQNameLengthTests {
    private func schema(_ facet: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v">
            <xs:simpleType>
              <xs:restriction base="xs:QName">\(facet)</xs:restriction>
            </xs:simpleType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("length, minLength, and maxLength never reject a valid QName")
    func test_lengthIsNonConstraining() throws {
        #expect(try schema(#"<xs:length value="1"/>"#).validate("<v>abcdefghij</v>").isEmpty)
        #expect(try schema(#"<xs:maxLength value="2"/>"#).validate("<v>abcdefghij</v>").isEmpty)
        #expect(try schema(#"<xs:minLength value="20"/>"#).validate("<v>abc</v>").isEmpty)
    }

    @Test("Lexical QName validity is still enforced")
    func test_qnameStillValidated() throws {
        // A leading digit is not a valid NCName, so not a valid QName.
        #expect(try !schema(#"<xs:length value="1"/>"#).validate("<v>1bad</v>").isEmpty)
    }
}
