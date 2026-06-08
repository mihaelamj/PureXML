@testable import PureXML
import Testing

@Suite("XSD derivation control")
struct XSDDerivationControlTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    /// A schema with an abstract `shape` head, a concrete `circle` member, and a
    /// `figure` element whose content references the head.
    private let substitution = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="shape" abstract="true" type="xs:string"/>
      <xs:element name="circle" type="xs:string" substitutionGroup="shape"/>
      <xs:element name="figure">
        <xs:complexType>
          <xs:sequence>
            <xs:element ref="shape"/>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    @Test("An abstract element may not appear at the document root")
    func test_abstractRootRejected() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="shape" abstract="true" type="xs:string"/>
        </xs:schema>
        """
        #expect(try !validate(xsd, "<shape>x</shape>").isEmpty)
    }

    @Test("An abstract head is not admitted in content, only its members")
    func test_abstractHeadInContent() throws {
        #expect(try !validate(substitution, "<figure><shape>x</shape></figure>").isEmpty)
        #expect(try validate(substitution, "<figure><circle>x</circle></figure>").isEmpty)
    }

    @Test("An element of abstract type requires xsi:type naming a concrete type")
    func test_abstractTypeNeedsXsiType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" abstract="true">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent>
              <xs:extension base="ShapeT">
                <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="ShapeT"/>
        </xs:schema>
        """
        #expect(try !validate(xsd, "<s><name>a</name></s>").isEmpty)
        #expect(try validate(xsd, "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"CircleT\"><name>a</name><radius>1</radius></s>").isEmpty)
    }

    @Test("block=extension on a type forbids xsi:type substitution by extension")
    func test_blockExtensionXsiType() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" block="extension">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent>
              <xs:extension base="ShapeT">
                <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
          <xs:complexType name="PointT">
            <xs:complexContent>
              <xs:restriction base="ShapeT">
                <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="ShapeT"/>
        </xs:schema>
        """
        // Substitution by extension is blocked.
        #expect(try !validate(xsd, "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"CircleT\"><name>a</name><radius>1</radius></s>").isEmpty)
        // Substitution by restriction is still permitted.
        #expect(try validate(xsd, "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"PointT\"><name>a</name></s>").isEmpty)
    }

    @Test("final=extension forbids deriving a new type by extension")
    func test_finalExtension() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" final="extension">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent>
              <xs:extension base="ShapeT">
                <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="CircleT"/>
        </xs:schema>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.Document(xsd)
        }
    }

    @Test("final=#all forbids both extension and restriction")
    func test_finalAll() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" final="#all">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="PointT">
            <xs:complexContent>
              <xs:restriction base="ShapeT">
                <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="PointT"/>
        </xs:schema>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.Document(xsd)
        }
    }

    @Test("xs:redefine requires the redefined type to derive from itself")
    func test_redefineSelfReference() throws {
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="T">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        let bad = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:redefine schemaLocation="base.xsd">
            <xs:complexType name="T">
              <xs:complexContent>
                <xs:extension base="Other">
                  <xs:sequence><xs:element name="b" type="xs:string"/></xs:sequence>
                </xs:extension>
              </xs:complexContent>
            </xs:complexType>
          </xs:redefine>
          <xs:element name="r" type="T"/>
        </xs:schema>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.Document(bad, schemaLoader: { _ in base })
        }
    }

    @Test("xs:redefine compiles when the type derives from itself")
    func test_redefineCompiles() throws {
        let base = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="T">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        let good = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:redefine schemaLocation="base.xsd">
            <xs:complexType name="T">
              <xs:complexContent>
                <xs:extension base="T">
                  <xs:sequence><xs:element name="b" type="xs:string"/></xs:sequence>
                </xs:extension>
              </xs:complexContent>
            </xs:complexType>
          </xs:redefine>
          <xs:element name="r" type="T"/>
        </xs:schema>
        """
        _ = try PureXML.Schema.Document(good, schemaLoader: { _ in base })
    }

    @Test("A concrete element with a non-blocked xsi:type still validates")
    func test_xsiTypeStillWorks() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent>
              <xs:extension base="ShapeT">
                <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="ShapeT"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"CircleT\"><name>a</name><radius>1</radius></s>").isEmpty)
    }
}
