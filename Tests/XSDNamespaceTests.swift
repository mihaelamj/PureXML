@testable import PureXML
import Testing

@Suite("XSD namespace qualification")
struct XSDNamespaceTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    @Test("A root element in the schema target namespace validates")
    func test_targetNamespaceRoot() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:books">
          <xs:element name="book" type="xs:string"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<book xmlns=\"urn:books\">x</book>").isEmpty)
    }

    @Test("A root element not in the target namespace is rejected")
    func test_targetNamespaceMismatch() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:books">
          <xs:element name="book" type="xs:string"/>
        </xs:schema>
        """
        // No namespace on the instance.
        #expect(try !validate(xsd, "<book>x</book>").isEmpty)
        // Wrong namespace on the instance.
        #expect(try !validate(xsd, "<book xmlns=\"urn:other\">x</book>").isEmpty)
    }

    @Test("elementFormDefault=qualified requires local children in the target namespace")
    func test_elementFormQualified() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:lib" elementFormDefault="qualified">
          <xs:element name="book">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="title" type="xs:string"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        // The default namespace qualifies both the root and the local child.
        #expect(try validate(xsd, "<book xmlns=\"urn:lib\"><title>x</title></book>").isEmpty)
        // An unqualified child does not match the qualified declaration.
        let mixed = "<book xmlns:l=\"urn:lib\" xmlns=\"urn:lib\"><title xmlns=\"\">x</title></book>"
        #expect(try !validate(xsd, mixed).isEmpty)
    }

    @Test("elementFormDefault=unqualified keeps local children in no namespace")
    func test_elementFormUnqualified() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:lib">
          <xs:element name="book">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="title" type="xs:string"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        // The root is qualified; the local child is unqualified, so it must carry no
        // namespace (the prefixed root keeps the default namespace off the child).
        let xml = "<l:book xmlns:l=\"urn:lib\"><title>x</title></l:book>"
        #expect(try validate(xsd, xml).isEmpty)
    }

    @Test("attributeFormDefault=qualified requires a qualified attribute")
    func test_attributeFormQualified() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:lib" elementFormDefault="qualified" attributeFormDefault="qualified">
          <xs:element name="book">
            <xs:complexType>
              <xs:attribute name="id" type="xs:string"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        // A prefixed (qualified) attribute matches the qualified declaration.
        #expect(try validate(xsd, "<l:book xmlns:l=\"urn:lib\" l:id=\"1\"/>").isEmpty)
        // An unqualified attribute is undeclared under attributeFormDefault=qualified.
        #expect(try !validate(xsd, "<l:book xmlns:l=\"urn:lib\" id=\"1\"/>").isEmpty)
    }

    @Test("xs:all with maxOccurs>1 on a member is a schema error")
    func test_allMemberMaxOccurs() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="rec">
            <xs:complexType>
              <xs:all>
                <xs:element name="a" type="xs:string" maxOccurs="2"/>
              </xs:all>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.Document(xsd)
        }
    }

    @Test("xs:all containing a nested model group is a schema error")
    func test_allNestedGroup() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="rec">
            <xs:complexType>
              <xs:all>
                <xs:sequence>
                  <xs:element name="a" type="xs:string"/>
                </xs:sequence>
              </xs:all>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.Document(xsd)
        }
    }

    @Test("A valid xs:all still compiles and validates order-independently")
    func test_allValid() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="rec">
            <xs:complexType>
              <xs:all>
                <xs:element name="a" type="xs:string"/>
                <xs:element name="b" type="xs:string"/>
              </xs:all>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<rec><b>2</b><a>1</a></rec>").isEmpty)
    }
}
