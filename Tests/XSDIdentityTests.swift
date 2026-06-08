@testable import PureXML
import Testing

@Suite("XSD identity constraints")
struct XSDIdentityTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    private let head = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"

    @Test("xs:unique rejects a duplicated field value")
    func test_unique() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:unique name="byId">
              <xs:selector xpath="item"/>
              <xs:field xpath="@id"/>
            </xs:unique>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<list><item id=\"1\"/><item id=\"2\"/></list>").isEmpty)
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>").isEmpty)
        // unique tolerates a missing field
        #expect(try validate(xsd, "<list><item/><item/></list>").isEmpty)
    }

    @Test("xs:key requires every field to be present and distinct")
    func test_key() throws {
        let xsd = """
        \(head)
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" type="xs:string" maxOccurs="unbounded"/></xs:sequence>
            </xs:complexType>
            <xs:key name="itemKey">
              <xs:selector xpath="item"/>
              <xs:field xpath="@id"/>
            </xs:key>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<list><item id=\"1\"/><item id=\"2\"/></list>").isEmpty)
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item id=\"1\"/></list>").isEmpty)
        // a key field may not be absent
        #expect(try !validate(xsd, "<list><item id=\"1\"/><item/></list>").isEmpty)
    }

    @Test("xs:keyref requires a matching key value")
    func test_keyref() throws {
        let xsd = """
        \(head)
          <xs:element name="orders">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="product" type="xs:string" maxOccurs="unbounded"/>
                <xs:element name="line" type="xs:string" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
            <xs:key name="prodKey">
              <xs:selector xpath="product"/>
              <xs:field xpath="@code"/>
            </xs:key>
            <xs:keyref name="lineRef" refer="prodKey">
              <xs:selector xpath="line"/>
              <xs:field xpath="@product"/>
            </xs:keyref>
          </xs:element>
        </xs:schema>
        """
        let valid = "<orders><product code=\"A\"/><product code=\"B\"/><line product=\"A\"/></orders>"
        let dangling = "<orders><product code=\"A\"/><line product=\"Z\"/></orders>"
        #expect(try validate(xsd, valid).isEmpty)
        #expect(try !validate(xsd, dangling).isEmpty)
    }
}
