import Testing
@testable import PureXML

/// cvc-elt.3.2.2: a nilled element (xsi:nil="true" on a nillable declaration) may
/// not have a fixed {value constraint}. A nillable element MAY carry a fixed value
/// at the schema level (the declaration is valid); the conflict is an instance
/// error only when that element is actually nilled. Mirrors XSTS addB065.
@Suite("nilled element with a fixed value constraint")
struct SchemaNilFixedTests {
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="r">
            <xs:complexType>
              <xs:sequence>
                <xs:element name="i" type="xs:string" minOccurs="0" maxOccurs="unbounded"
                            nillable="true" fixed="abc"/>
                <xs:element name="j" type="xs:string" minOccurs="0" nillable="true"/>
              </xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """)
    }

    private let xsi = #"xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance""#

    @Test("the schema (nillable element with a fixed value) compiles")
    func test_schemaValid() throws {
        _ = try schema() // does not throw
    }

    @Test("nilling a fixed-valued element is rejected")
    func test_nilledFixedRejected() throws {
        #expect(try !schema().validate(#"<r \#(xsi)><i xsi:nil="true"/></r>"#).isEmpty)
    }

    @Test("supplying the fixed value (not nilling) is accepted")
    func test_fixedValueAccepted() throws {
        #expect(try schema().validate(#"<r \#(xsi)><i>abc</i></r>"#).isEmpty)
    }

    @Test("nilling a nillable element with no fixed value stays valid")
    func test_nilledNoFixedAccepted() throws {
        #expect(try schema().validate(#"<r \#(xsi)><j xsi:nil="true"/></r>"#).isEmpty)
    }
}
