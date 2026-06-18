import Testing
@testable import PureXML

@Suite("XSD includes, substitution groups, xsi:type")
struct XSDImportTests {
    private func validate(
        _ xsd: String,
        _ xml: String,
        loader: @escaping (String) -> String? = { _ in nil },
    ) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd, schemaLoader: loader).validate(xml)
    }

    @Test("xs:include pulls in another schema's named type")
    func test_include() throws {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string"><xs:pattern value="[A-Z]{3}"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        let loader: (String) -> String? = { $0 == "lib.xsd" ? library : nil }
        #expect(try validate(main, "<code>ABC</code>", loader: loader).isEmpty)
        #expect(try !validate(main, "<code>abc</code>", loader: loader).isEmpty)
    }

    @Test("xs:redefine overrides an included type")
    func test_redefine() throws {
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="quantity">
            <xs:restriction base="xs:integer"><xs:maxInclusive value="100"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:redefine schemaLocation="base.xsd">
            <xs:simpleType name="quantity">
              <xs:restriction base="quantity"><xs:maxInclusive value="10"/></xs:restriction>
            </xs:simpleType>
          </xs:redefine>
          <xs:element name="q" type="quantity"/>
        </xs:schema>
        """
        let loader: (String) -> String? = { $0 == "base.xsd" ? base : nil }
        #expect(try validate(main, "<q>5</q>", loader: loader).isEmpty)
        #expect(try !validate(main, "<q>50</q>", loader: loader).isEmpty)
    }

    @Test("A substitution-group member is accepted where the head is referenced")
    func test_substitutionGroup() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="shape" type="xs:string"/>
          <xs:element name="circle" type="xs:string" substitutionGroup="shape"/>
          <xs:element name="canvas">
            <xs:complexType>
              <xs:sequence>
                <xs:element ref="shape" maxOccurs="unbounded"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<canvas><shape>a</shape><circle>b</circle></canvas>").isEmpty)
        #expect(try !validate(xsd, "<canvas><square>b</square></canvas>").isEmpty)
    }

    @Test("xsi:type overrides the declared type at the instance")
    func test_xsiType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base"><xs:sequence/></xs:complexType>
          <xs:complexType name="withValue">
            <xs:sequence><xs:element name="v" type="xs:integer"/></xs:sequence>
          </xs:complexType>
          <xs:element name="item" type="base"/>
        </xs:schema>
        """
        let valid = "<item xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"withValue\"><v>3</v></item>"
        let invalid = "<item xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"withValue\"><v>x</v></item>"
        #expect(try validate(xsd, valid).isEmpty)
        #expect(try !validate(xsd, invalid).isEmpty)
    }
}
