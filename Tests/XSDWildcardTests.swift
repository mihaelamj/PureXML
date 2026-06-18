import Testing
@testable import PureXML

@Suite("XSD wildcards and list builtins")
struct XSDWildcardTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    @Test("xs:any with processContents=skip admits any element without validating it")
    func test_anySkip() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="box">
            <xs:complexType>
              <xs:sequence>
                <xs:any processContents="skip" minOccurs="0" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<box><anything/><else>x</else></box>").isEmpty)
    }

    @Test("xs:any with processContents=strict requires a global declaration")
    func test_anyStrict() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="known" type="xs:integer"/>
          <xs:element name="box">
            <xs:complexType>
              <xs:sequence>
                <xs:any processContents="strict" minOccurs="0" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        // A declared element validates against its declaration through the wildcard.
        #expect(try validate(xsd, "<box><known>1</known></box>").isEmpty)
        #expect(try !validate(xsd, "<box><known>x</known></box>").isEmpty)
        // An undeclared element is rejected under strict.
        #expect(try !validate(xsd, "<box><mystery/></box>").isEmpty)
    }

    @Test("xs:anyAttribute admits undeclared attributes")
    func test_anyAttribute() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="item">
            <xs:complexType>
              <xs:attribute name="id" type="xs:string"/>
              <xs:anyAttribute processContents="skip"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<item id=\"1\" extra=\"y\" more=\"z\"/>").isEmpty)
    }

    @Test("Undeclared attributes are still rejected without a wildcard")
    func test_noWildcardRejects() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="item">
            <xs:complexType>
              <xs:attribute name="id" type="xs:string"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try !validate(xsd, "<item id=\"1\" extra=\"y\"/>").isEmpty)
    }

    @Test("List built-in datatypes validate each item")
    func test_listBuiltins() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="tokens" type="xs:NMTOKENS"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<tokens>a b c</tokens>").isEmpty)
        // A space is not a valid NMTOKEN item, but spaces separate items, so this
        // tests that an item with an illegal character is rejected.
        #expect(try !validate(xsd, "<tokens>a b@d</tokens>").isEmpty)
    }
}
