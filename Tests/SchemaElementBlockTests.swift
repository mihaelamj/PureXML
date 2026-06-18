import Testing
@testable import PureXML

/// `block` on an element declaration forbids substituting a type derived from
/// the declared type by a listed method via `xsi:type`, distinct from `block`
/// on the type itself (#147, XSTS elemT set). The element-level block was parsed
/// but never enforced, so blocked substitutions were wrongly accepted.
@Suite("Element-level block on xsi:type substitution")
struct SchemaElementBlockTests {
    private func schema(block: String) throws -> PureXML.Schema.Document {
        let attribute = block.isEmpty ? "" : " block=\"\(block)\""
        return try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType><xs:sequence>
              <xs:element ref="foo"/>
            </xs:sequence></xs:complexType>
          </xs:element>
          <xs:element name="foo" type="Base"\(attribute)/>
          <xs:complexType name="Base">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="Restricted">
            <xs:complexContent>
              <xs:restriction base="Base">
                <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """)
    }

    private let instance = #"<root><foo xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="Restricted"><a>x</a></foo></root>"#

    @Test("block='restriction' on an element rejects a restriction xsi:type")
    func test_elementBlockRejectsRestriction() throws {
        #expect(try !schema(block: "restriction").validate(instance).isEmpty)
    }

    @Test("an element without block accepts the same restriction xsi:type")
    func test_noBlockAcceptsRestriction() throws {
        #expect(try schema(block: "").validate(instance).isEmpty)
    }

    @Test("block='extension' does not block a restriction substitution")
    func test_unrelatedBlockDoesNotReject() throws {
        #expect(try schema(block: "extension").validate(instance).isEmpty)
    }
}
