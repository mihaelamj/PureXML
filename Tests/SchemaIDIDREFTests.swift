@testable import PureXML
import Testing

/// Document-scoped xs:ID/xs:IDREF validation (#147, XSTS idConstrDefs set):
/// every xs:ID value is unique across the document, and every xs:IDREF/xs:IDREFS
/// item matches some ID. These had been checked only lexically (as NCNames).
@Suite("ID and IDREF document constraints")
struct SchemaIDIDREFTests {
    private var schema: PureXML.Schema.Document {
        get throws {
            try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:element name="root">
                <xs:complexType>
                  <xs:choice minOccurs="0" maxOccurs="unbounded">
                    <xs:element name="id" type="xs:ID"/>
                    <xs:element name="ref" type="xs:IDREF"/>
                    <xs:element name="refs" type="xs:IDREFS"/>
                  </xs:choice>
                </xs:complexType>
              </xs:element>
            </xs:schema>
            """)
        }
    }

    @Test("Unique IDs and a resolving reference validate")
    func test_valid() throws {
        #expect(try schema.validate("<root><id>a</id><id>b</id><ref>a</ref></root>").isEmpty)
    }

    @Test("A forward IDREF resolves against an ID declared later")
    func test_forwardReference() throws {
        #expect(try schema.validate("<root><ref>a</ref><id>a</id></root>").isEmpty)
    }

    @Test("A duplicate ID is rejected")
    func test_duplicateID() throws {
        #expect(try !schema.validate("<root><id>a</id><id>a</id></root>").isEmpty)
    }

    @Test("An IDREF with no matching ID is rejected")
    func test_unresolvedReference() throws {
        #expect(try !schema.validate("<root><id>a</id><ref>x</ref></root>").isEmpty)
    }

    @Test("IDREFS resolves each item; one unmatched item fails")
    func test_idrefs() throws {
        #expect(try schema.validate("<root><id>a</id><id>b</id><refs>a b</refs></root>").isEmpty)
        #expect(try !schema.validate("<root><id>a</id><refs>a x</refs></root>").isEmpty)
    }
}
