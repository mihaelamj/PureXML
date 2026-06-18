import Testing
@testable import PureXML

/// An `xsi:type` may not name an abstract type: an abstract type cannot be the
/// type of an instance element (cvc-elt.4.3.2), so it is invalid as a substitution
/// even when the declared type would otherwise admit it. A concrete derived type
/// is accepted.
@Suite("abstract xsi:type")
struct SchemaAbstractXsiTypeTests {
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns="u" xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="u">
          <xs:element name="root"/>
          <xs:complexType name="Real"/>
          <xs:complexType name="Virtual" abstract="true"/>
        </xs:schema>
        """)
    }

    private func doc(_ type: String) -> String {
        #"<root xmlns="u" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="\#(type)"/>"#
    }

    @Test("an abstract xsi:type is rejected")
    func test_abstractRejected() throws {
        #expect(try !schema().validate(doc("Virtual")).isEmpty)
    }

    @Test("a concrete xsi:type is accepted")
    func test_concreteAccepted() throws {
        #expect(try schema().validate(doc("Real")).isEmpty)
    }
}
