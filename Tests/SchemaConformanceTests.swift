import Testing
@testable import PureXML

/// Cross-cutting conformance fixtures for both schema languages: realistic
/// schemas validated against valid and invalid instances.
@Suite("Schema conformance")
struct SchemaConformanceTests {
    // MARK: A realistic XSD: a purchase order

    private let purchaseOrderXSD = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:simpleType name="sku">
        <xs:restriction base="xs:string">
          <xs:pattern value="\\d{3}-[A-Z]{2}"/>
        </xs:restriction>
      </xs:simpleType>
      <xs:simpleType name="quantity">
        <xs:restriction base="xs:positiveInteger">
          <xs:maxInclusive value="999"/>
        </xs:restriction>
      </xs:simpleType>
      <xs:complexType name="item">
        <xs:sequence>
          <xs:element name="sku" type="sku"/>
          <xs:element name="qty" type="quantity"/>
        </xs:sequence>
      </xs:complexType>
      <xs:element name="order">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="item" type="item" maxOccurs="unbounded"/>
          </xs:sequence>
          <xs:attribute name="id" type="xs:ID" use="required"/>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    @Test("Purchase order: a fully conforming document")
    func test_orderValid() throws {
        let schema = try PureXML.Schema.Document(purchaseOrderXSD)
        let xml = """
        <order id="A1"><item><sku>123-AB</sku><qty>5</qty></item>\
        <item><sku>999-ZZ</sku><qty>999</qty></item></order>
        """
        #expect(try schema.validate(xml).isEmpty)
    }

    @Test("Purchase order: each constraint is enforced")
    func test_orderViolations() throws {
        let schema = try PureXML.Schema.Document(purchaseOrderXSD)
        // Bad SKU pattern.
        #expect(try !schema.validate("<order id=\"A1\"><item><sku>bad</sku><qty>5</qty></item></order>").isEmpty)
        // Quantity above the maxInclusive.
        #expect(try !schema.validate("<order id=\"A1\"><item><sku>123-AB</sku><qty>1000</qty></item></order>").isEmpty)
        // Quantity not positive.
        #expect(try !schema.validate("<order id=\"A1\"><item><sku>123-AB</sku><qty>0</qty></item></order>").isEmpty)
        // Missing the required id attribute.
        #expect(try !schema.validate("<order><item><sku>123-AB</sku><qty>5</qty></item></order>").isEmpty)
        // At least one item is required.
        #expect(try !schema.validate("<order id=\"A1\"></order>").isEmpty)
    }

    // MARK: A realistic RELAX NG: a contact card with attributes and interleave

    private let contactRNG = """
    <grammar xmlns="http://relaxng.org/ns/structure/1.0">
      <start><ref name="contact"/></start>
      <define name="contact">
        <element name="contact">
          <attribute name="kind"><choice><value>person</value><value>company</value></choice></attribute>
          <interleave>
            <element name="name"><text/></element>
            <optional><element name="email"><data type="string"/></element></optional>
            <zeroOrMore><element name="phone"><text/></element></zeroOrMore>
          </interleave>
        </element>
      </define>
    </grammar>
    """

    @Test("Contact: valid documents in varying order")
    func test_contactValid() throws {
        let schema = try PureXML.Schema.RelaxNG(contactRNG)
        #expect(try schema.validate("<contact kind=\"person\"><name>Ada</name></contact>"))
        #expect(try schema.validate("""
        <contact kind="company"><phone>1</phone><name>Acme</name>\
        <email>a@b.c</email><phone>2</phone></contact>
        """))
    }

    @Test("Contact: invalid documents are rejected")
    func test_contactInvalid() throws {
        let schema = try PureXML.Schema.RelaxNG(contactRNG)
        // Missing the required kind attribute.
        #expect(try !schema.validate("<contact><name>Ada</name></contact>"))
        // kind not one of the allowed values.
        #expect(try !schema.validate("<contact kind=\"robot\"><name>Ada</name></contact>"))
        // Missing the required name element.
        #expect(try !schema.validate("<contact kind=\"person\"><email>a@b.c</email></contact>"))
        // Two names (name is not repeatable).
        #expect(try !schema.validate("<contact kind=\"person\"><name>A</name><name>B</name></contact>"))
    }

    // MARK: Datatype boundary fixtures

    private struct DatatypeCase {
        let value: String
        let type: PureXML.Schema.BuiltinType
        let expected: Bool
    }

    @Test("Datatype boundaries across the type library")
    func test_datatypeBoundaries() {
        let cases: [DatatypeCase] = [
            .init(value: "2024-02-29", type: .date, expected: true),
            .init(value: "2025-02-29", type: .date, expected: false),
            .init(value: "9223372036854775807", type: .long, expected: true),
            .init(value: "9223372036854775808", type: .long, expected: false),
            .init(value: "P1Y", type: .duration, expected: true),
            .init(value: "1Y", type: .duration, expected: false),
            .init(value: "0.1", type: .decimal, expected: true),
            .init(value: "1.0e3", type: .decimal, expected: false),
            .init(value: "true", type: .boolean, expected: true),
            .init(value: "urn:example:x", type: .anyURI, expected: true),
        ]
        for testCase in cases {
            #expect(
                PureXML.Schema.isValid(testCase.value, type: testCase.type) == testCase.expected,
                "\(testCase.value) as \(testCase.type.rawValue)",
            )
        }
    }
}
