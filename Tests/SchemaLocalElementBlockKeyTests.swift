@testable import PureXML
import Testing

/// A `block` on a LOCAL element declaration applies to that element by its instance
/// (qualified) name. When the schema is unqualified (no elementFormDefault), the
/// local element is in no namespace, so the block must be keyed there for an
/// xsi:type substitution on it to be barred (W3C sun typeDef00801).
@Suite("local element block keying")
struct SchemaLocalElementBlockKeyTests {
    @Test("block on an unqualified local element bars an xsi:type extension")
    func test_unqualifiedLocalElementBlock() throws {
        let schema = try PureXML.Schema.Document("""
        <xsd:schema xmlns="u" xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="u">
          <xsd:element name="root"><xsd:complexType><xsd:sequence>
            <xsd:element name="Element" type="Type" block="extension"/>
          </xsd:sequence></xsd:complexType></xsd:element>
          <xsd:complexType name="Type"><xsd:attribute name="value" type="xsd:boolean"/></xsd:complexType>
          <xsd:complexType name="derivedType"><xsd:complexContent>
            <xsd:extension base="Type"><xsd:attribute name="value1" type="xsd:boolean"/></xsd:extension>
          </xsd:complexContent></xsd:complexType>
        </xsd:schema>
        """)
        // Element is unqualified (no elementFormDefault): in instance it is in no namespace.
        let doc = #"<test:root xmlns:test="u" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"><Element xsi:type="test:derivedType" value="false" value1="true"/></test:root>"#
        #expect(try !schema.validate(doc).isEmpty)
    }
}
