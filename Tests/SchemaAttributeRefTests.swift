@testable import PureXML
import Testing

/// An `<xs:attribute ref="...">` resolves to a global attribute declaration,
/// taking its type from the global node and its use/default/fixed from the
/// reference site (#147, XSTS attgD set). References were dropped (they have no
/// `name`), so a referenced attribute looked undeclared on the instance.
@Suite("Attribute references in attribute groups")
struct SchemaAttributeRefTests {
    private var schema: PureXML.Schema.Document {
        get throws {
            try PureXML.Schema.Document("""
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:attribute name="a1" type="xs:string"/>
              <xs:element name="doc">
                <xs:complexType>
                  <xs:attributeGroup ref="g"/>
                </xs:complexType>
              </xs:element>
              <xs:attributeGroup name="g">
                <xs:attribute ref="a1"/>
                <xs:attribute name="a2" type="xs:int"/>
              </xs:attributeGroup>
            </xs:schema>
            """)
        }
    }

    @Test("A referenced global attribute is admitted on the instance")
    func test_referencedAttributeAdmitted() throws {
        #expect(try schema.validate(#"<doc a1="x" a2="5"/>"#).isEmpty)
    }

    @Test("The referenced attribute keeps the global declaration's type")
    func test_refTypeEnforced() throws {
        // a2 is xs:int via inline declaration; a non-integer is rejected.
        #expect(try !schema.validate(#"<doc a1="x" a2="notint"/>"#).isEmpty)
    }

    @Test("An attribute outside the (nested) group is still undeclared")
    func test_undeclaredStillRejected() throws {
        #expect(try !schema.validate(#"<doc a1="x" a2="5" a3="y"/>"#).isEmpty)
    }
}
