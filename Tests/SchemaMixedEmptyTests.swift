import Testing
@testable import PureXML

/// A `mixed="true"` complex type with no content model (only attributes) still
/// permits character data: it is mixed content over an empty particle, not the
/// empty content type, which forbids text (#147, XSTS attgD set). Child elements
/// are still not allowed, and a non-mixed empty type still rejects text.
@Suite("Mixed content with no element model")
struct SchemaMixedEmptyTests {
    private func schema(mixed: Bool) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="doc">
            <xs:complexType\(mixed ? " mixed=\"true\"" : "")>
              <xs:attribute name="a" type="xs:string"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("A mixed empty type permits text and stays empty of elements")
    func test_mixedAllowsText() throws {
        let doc = try schema(mixed: true)
        #expect(try doc.validate(#"<doc a="x">hello</doc>"#).isEmpty) // text allowed
        #expect(try doc.validate(#"<doc a="x"/>"#).isEmpty) // empty allowed
        #expect(try !doc.validate(#"<doc a="x"><child/></doc>"#).isEmpty) // no element content
    }

    @Test("A non-mixed empty type still rejects text")
    func test_nonMixedRejectsText() throws {
        #expect(try !schema(mixed: false).validate(#"<doc a="x">hello</doc>"#).isEmpty)
    }
}
