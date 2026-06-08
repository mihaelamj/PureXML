@testable import PureXML
import Testing

@Suite("XSD nillable and value constraints")
struct XSDValueConstraintTests {
    private func validate(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    private let xsi = "xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\""

    @Test("A nillable element accepts xsi:nil with empty content")
    func test_nillableEmpty() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="age" type="xs:integer" nillable="true"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<age \(xsi) xsi:nil=\"true\"/>").isEmpty)
        // Even though the content would otherwise have to be an integer.
        #expect(try validate(xsd, "<age>notanumber</age>").isEmpty == false)
    }

    @Test("A nilled element must be empty")
    func test_nilMustBeEmpty() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="age" type="xs:integer" nillable="true"/>
        </xs:schema>
        """
        let found = try validate(xsd, "<age \(xsi) xsi:nil=\"true\">5</age>")
        #expect(found.count == 1)
        #expect(found[0].reason.contains("must be empty"))
    }

    @Test("xsi:nil on a non-nillable element is rejected")
    func test_nilNotNillable() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="age" type="xs:integer"/>
        </xs:schema>
        """
        let found = try validate(xsd, "<age \(xsi) xsi:nil=\"true\"/>")
        #expect(found.count == 1)
        #expect(found[0].reason.contains("not nillable"))
    }

    @Test("A fixed attribute must carry its fixed value")
    func test_fixedAttribute() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="item">
            <xs:complexType>
              <xs:attribute name="kind" type="xs:string" fixed="book"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        #expect(try validate(xsd, "<item kind=\"book\"/>").isEmpty)
        #expect(try validate(xsd, "<item/>").isEmpty)
        let found = try validate(xsd, "<item kind=\"film\"/>")
        #expect(found.count == 1)
        #expect(found[0].reason.contains("is fixed and must be 'book'"))
    }

    @Test("A fixed element value must match")
    func test_fixedElement() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="version" type="xs:string" fixed="1.0"/>
        </xs:schema>
        """
        #expect(try validate(xsd, "<version>1.0</version>").isEmpty)
        let found = try validate(xsd, "<version>2.0</version>")
        #expect(found.count == 1)
        #expect(found[0].reason.contains("is fixed and must be '1.0'"))
    }
}
