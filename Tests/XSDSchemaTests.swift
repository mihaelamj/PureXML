import Testing
@testable import PureXML

@Suite("XSD schema documents")
struct XSDSchemaTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    @Test("A nested type violation is located by coding path")
    func test_violationCarriesPath() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="order">
            <xs:complexType>
              <xs:sequence><xs:element name="qty" type="xs:integer"/></xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let found = try validate(xsd, "<order><qty>lots</qty></order>")
        #expect(found.count == 1)
        #expect(String(describing: found[0]).hasSuffix("at path: order/qty"))
    }

    @Test("A simple element with a built-in type")
    func test_simpleElement() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="age" type="xs:nonNegativeInteger"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<age>30</age>").isEmpty)
        #expect(try !validate(xsd, "<age>-5</age>").isEmpty)
        #expect(try !validate(xsd, "<age>x</age>").isEmpty)
    }

    @Test("A named simpleType with facets")
    func test_namedSimpleType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string">
              <xs:pattern value="[A-Z]{3}-\\d{4}"/>
            </xs:restriction>
          </xs:simpleType>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<code>ABC-1234</code>").isEmpty)
        #expect(try !validate(xsd, "<code>abc-1234</code>").isEmpty)
    }

    @Test("A complex type with a sequence and attributes")
    func test_complexType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="book">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="title" type="xs:string"/>
                <xs:element name="year" type="xs:gYear" minOccurs="0"/>
              </xs:sequence>
              <xs:attribute name="isbn" type="xs:string" use="required"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<book isbn=\"1\"><title>T</title><year>2026</year></book>").isEmpty)
        #expect(try validate(xsd, "<book isbn=\"1\"><title>T</title></book>").isEmpty)
        #expect(try !validate(xsd, "<book><title>T</title></book>").isEmpty) // missing isbn
        #expect(try !validate(xsd, "<book isbn=\"1\"><year>2026</year></book>").isEmpty) // missing title
        #expect(try !validate(xsd, "<book isbn=\"1\"><title>T</title><year>nope</year></book>").isEmpty)
    }

    @Test("A huge finite maxOccurs is preserved beyond Int range")
    func test_hugeFiniteMaxOccurs() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="root">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="item" type="xs:string" maxOccurs="100000000000000000000"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<root><item/><item/></root>").isEmpty)
        #expect(try !validate(xsd, "<root/>").isEmpty)
    }

    @Test("A named complex type referenced by elements")
    func test_namedComplexType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="point">
            <xs:sequence>
              <xs:element name="x" type="xs:decimal"/>
              <xs:element name="y" type="xs:decimal"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="location" type="point"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<location><x>1.5</x><y>2.5</y></location>").isEmpty)
        #expect(try !validate(xsd, "<location><x>1.5</x></location>").isEmpty)
    }

    @Test("Recursive types validate to any depth")
    func test_recursiveType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="node">
            <xs:sequence>
              <xs:element name="value" type="xs:int"/>
              <xs:element name="child" type="node" minOccurs="0"/>
            </xs:sequence>
          </xs:complexType>
          <xs:element name="tree" type="node"/>
        </xs:schema>
        """
        let nested = "<tree><value>1</value><child><value>2</value><child><value>3</value></child></child></tree>"
        #expect(try validate(xsd, nested).isEmpty)
        let bad = "<tree><value>1</value><child><value>x</value></child></tree>"
        #expect(try !validate(xsd, bad).isEmpty)
    }

    @Test("Simple content restricts the text and keeps attributes")
    func test_simpleContent() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="price">
            <xs:complexType>
              <xs:simpleContent>
                <xs:extension base="xs:decimal">
                  <xs:attribute name="currency" type="xs:string"/>
                </xs:extension>
              </xs:simpleContent>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<price currency=\"USD\">9.99</price>").isEmpty)
        #expect(try !validate(xsd, "<price>nope</price>").isEmpty)
    }

    @Test("An unknown root element is reported")
    func test_unknownRoot() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="known" type="xs:string"/>
        </xs:schema>
        """
        #expect(try !validate(xsd, "<unknown/>").isEmpty)
    }
}
