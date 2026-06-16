@testable import PureXML
import Testing

@Suite("XSD include composition (#161)")
struct SchemaIncludeTests {
    @Test("chameleon include: no-namespace library merges into a target-namespace main schema")
    func test_chameleonIncludeWithTargetNamespace() throws {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string"><xs:pattern value="[A-Z]{3}"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        #expect(try doc.validate("<code xmlns=\"urn:main\">ABC</code>").isEmpty)
        #expect(try !doc.validate("<code xmlns=\"urn:main\">abc</code>").isEmpty)
    }

    @Test("xs:include with a mismatched targetNamespace is rejected")
    func test_invalidIncludeDifferentTargetNamespace() {
        let included = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:other">
          <xs:element name="e" type="xs:string"/>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="other.xsd"/>
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
        """
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "other.xsd" ? included : nil })
        }
    }

    @Test("xs:include with matching targetNamespace is accepted")
    func test_includeMatchingTargetNamespace() throws {
        let included = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string"><xs:pattern value="[A-Z]{3}"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? included : nil })
        #expect(try doc.validate("<code xmlns=\"urn:main\">ABC</code>").isEmpty)
    }

    @Test("chameleon include: attribute refs inside the included schema resolve after merge")
    func test_chameleonIncludeAttributeGroupRef() throws {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attribute name="a1" type="xs:string"/>
          <xs:attributeGroup name="g">
            <xs:attribute ref="a1"/>
          </xs:attributeGroup>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="doc">
            <xs:complexType>
              <xs:attributeGroup ref="g"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        #expect(try doc.validate("<doc xmlns=\"urn:main\" a1=\"x\"/>").isEmpty)
    }

    @Test("undeclared refs inside an included chameleon schema are rejected at compile time")
    func test_invalidReferenceInsideIncludedSchema() {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attributeGroup name="g">
            <xs:attribute ref="missing"/>
          </xs:attributeGroup>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
        </xs:schema>
        """
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        }
    }
}
