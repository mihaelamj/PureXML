@testable import PureXML
import Testing

/// Identity-constraint field values are compared in their shared value space. Two
/// fields typed by different members of the decimal-derived numeric family (e.g.
/// `xs:decimal` and `xs:unsignedByte`, selected via `xsi:type`) denote the same
/// value when their numbers are equal, so `1` and `1` collide for a `unique`.
/// Values in distinct primitive spaces never collide.
@Suite("Identity-constraint cross-type value equality")
struct SchemaIdentityValueEqualityTests {
    /// Mirrors the W3C idF015 shape: an `xsd:anyType` element whose instances carry
    /// `xsi:type` numeric overrides, gathered by a `unique`.
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" elementFormDefault="qualified">
          <xsd:element name="root">
            <xsd:complexType><xsd:sequence>
              <xsd:element ref="uid" maxOccurs="unbounded"/>
            </xsd:sequence></xsd:complexType>
            <xsd:unique name="u"><xsd:selector xpath=".//uid"/><xsd:field xpath="."/></xsd:unique>
          </xsd:element>
          <xsd:element name="uid" type="xsd:anyType"/>
        </xsd:schema>
        """)
    }

    private func doc(_ decimalValue: String, _ unsignedValue: String) -> String {
        """
        <root xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <uid xsi:type="xsd:decimal">\(decimalValue)</uid>
          <uid xsi:type="xsd:unsignedByte">\(unsignedValue)</uid>
        </root>
        """
    }

    @Test("decimal and unsignedByte with the same number collide for unique")
    func test_crossNumericTypesCollide() throws {
        // 1 (decimal) and 1 (unsignedByte) are one value in the decimal value space.
        #expect(try !schema().validate(doc("1", "1")).isEmpty)
        // 1.0 (decimal) and 1 (unsignedByte) likewise.
        #expect(try !schema().validate(doc("1.0", "1")).isEmpty)
        // Distinct numbers do not collide.
        #expect(try schema().validate(doc("1", "2")).isEmpty)
    }
}
