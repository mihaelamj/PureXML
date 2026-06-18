@testable import PureXML
import Testing

/// A schema `blockDefault` supplies the `{disallowed substitutions}` of an element
/// and the `{prohibited substitutions}` of a complex type that state no `block` of
/// their own, blocking an `xsi:type` substitution by a listed derivation method
/// (XSD 1.0 Structures section 3.3.2 / 3.4.2; cvc-elt.4.3.2.1). An explicit
/// `block=""` overrides the default back to acceptance.
@Suite("schema blockDefault on xsi:type substitution")
struct SchemaBlockDefaultTests {
    /// A schema with the given `blockDefault` plus optional explicit `block`
    /// overrides on the element and its declared type. `ShapeT` is the declared
    /// type; `CircleT` extends it and `PointT` restricts it.
    private func schema(blockDefault: String, elementBlock: String? = nil, typeBlock: String? = nil) -> String {
        let defaultAttribute = blockDefault.isEmpty ? "" : " blockDefault=\"\(blockDefault)\""
        let elementAttribute = elementBlock.map { " block=\"\($0)\"" } ?? ""
        let typeAttribute = typeBlock.map { " block=\"\($0)\"" } ?? ""
        return """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"\(defaultAttribute)>
          <xs:complexType name="ShapeT"\(typeAttribute)>
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
          <xs:element name="s" type="ShapeT"\(elementAttribute)/>
        </xs:schema>
        """
    }

    private let extensionInstance =
        "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"CircleT\"><name>a</name><radius>1</radius></s>"
    private let restrictionInstance =
        "<s xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\" xsi:type=\"PointT\"><name>a</name></s>"

    private func validate(_ xsd: String, _ instance: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(instance)
    }

    @Test("blockDefault=extension blocks an extension xsi:type")
    func test_blockDefaultBlocksExtension() throws {
        #expect(try !validate(schema(blockDefault: "extension"), extensionInstance).isEmpty)
    }

    @Test("blockDefault=extension still allows a restriction xsi:type")
    func test_blockDefaultAllowsRestriction() throws {
        #expect(try validate(schema(blockDefault: "extension"), restrictionInstance).isEmpty)
    }

    @Test("blockDefault=#all blocks both extension and restriction")
    func test_blockDefaultAllBlocksBoth() throws {
        #expect(try !validate(schema(blockDefault: "#all"), extensionInstance).isEmpty)
        #expect(try !validate(schema(blockDefault: "#all"), restrictionInstance).isEmpty)
    }

    @Test("explicit block=\"\" on the element and its type overrides blockDefault back to acceptance")
    func test_emptyBlockOverridesDefault() throws {
        // cvc-elt.4.3.2.1 unions the element's {disallowed substitutions} with the
        // declared type's {prohibited substitutions}, so both must be cleared.
        let xsd = schema(blockDefault: "#all", elementBlock: "", typeBlock: "")
        #expect(try validate(xsd, extensionInstance).isEmpty)
        #expect(try validate(xsd, restrictionInstance).isEmpty)
    }
}
