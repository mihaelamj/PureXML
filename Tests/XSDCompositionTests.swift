import Testing
@testable import PureXML

@Suite("XSD list, union, groups, and references")
struct XSDCompositionTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    @Test("A list simple type validates each whitespace-separated item")
    func test_listType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="ints">
            <xs:list itemType="xs:integer"/>
          </xs:simpleType>
          <xs:element name="nums" type="ints"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<nums>1 2 3</nums>").isEmpty)
        #expect(try !validate(xsd, "<nums>1 x 3</nums>").isEmpty)
    }

    @Test("A restricted list bounds its item count")
    func test_listLength() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="pair">
            <xs:restriction base="couples">
              <xs:length value="2"/>
            </xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="couples">
            <xs:list itemType="xs:string"/>
          </xs:simpleType>
          <xs:element name="p" type="pair"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<p>a b</p>").isEmpty)
        #expect(try !validate(xsd, "<p>a b c</p>").isEmpty)
    }

    @Test("A union admits a value valid for any member type")
    func test_unionType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="sizeOrAuto">
            <xs:union memberTypes="xs:nonNegativeInteger">
              <xs:simpleType>
                <xs:restriction base="xs:string"><xs:enumeration value="auto"/></xs:restriction>
              </xs:simpleType>
            </xs:union>
          </xs:simpleType>
          <xs:element name="w" type="sizeOrAuto"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<w>10</w>").isEmpty)
        #expect(try validate(xsd, "<w>auto</w>").isEmpty)
        #expect(try !validate(xsd, "<w>-1</w>").isEmpty)
        #expect(try !validate(xsd, "<w>tiny</w>").isEmpty)
    }

    @Test("An attribute group is expanded into the referencing type")
    func test_attributeGroup() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attributeGroup name="dims">
            <xs:attribute name="w" type="xs:integer" use="required"/>
            <xs:attribute name="h" type="xs:integer" use="required"/>
          </xs:attributeGroup>
          <xs:element name="box">
            <xs:complexType>
              <xs:attributeGroup ref="dims"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<box w=\"3\" h=\"4\"/>").isEmpty)
        #expect(try !validate(xsd, "<box w=\"3\"/>").isEmpty)
        #expect(try !validate(xsd, "<box w=\"x\" h=\"4\"/>").isEmpty)
    }

    @Test("A named model group is expanded at its reference")
    func test_groupReference() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:group name="titleAndBody">
            <xs:sequence>
              <xs:element name="title" type="xs:string"/>
              <xs:element name="body" type="xs:string"/>
            </xs:sequence>
          </xs:group>
          <xs:element name="doc">
            <xs:complexType>
              <xs:sequence>
                <xs:group ref="titleAndBody"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<doc><title>A</title><body>B</body></doc>").isEmpty)
        #expect(try !validate(xsd, "<doc><body>B</body></doc>").isEmpty)
    }

    @Test("An element reference resolves to the global declaration's type")
    func test_elementReference() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="sku" type="xs:nonNegativeInteger"/>
          <xs:element name="order">
            <xs:complexType>
              <xs:sequence>
                <xs:element ref="sku" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<order><sku>1</sku><sku>2</sku></order>").isEmpty)
        #expect(try !validate(xsd, "<order><sku>-1</sku></order>").isEmpty)
        #expect(try !validate(xsd, "<order><other>1</other></order>").isEmpty)
    }
}
