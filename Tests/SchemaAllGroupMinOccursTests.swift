import Testing
@testable import PureXML

/// An `xs:all` group's own `minOccurs="0"` makes the GROUP optional (it occurs
/// zero or one times), not its members optional. An absent group (no children)
/// is valid; a present group (any child) must still satisfy each member's own
/// `minOccurs`. Earlier the parser forced every member's `minOccurs` to 0, so a
/// non-empty but incomplete optional all-group was wrongly accepted. Mirrors XSTS
/// mgZ001.
@Suite("optional xs:all group member requirements")
struct SchemaAllGroupMinOccursTests {
    private func schema() throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="opt">
            <xs:complexType>
              <xs:all minOccurs="0">
                <xs:element name="a"/>
                <xs:element name="b" minOccurs="0"/>
                <xs:element name="c"/>
              </xs:all>
            </xs:complexType>
          </xs:element>
          <xs:element name="req">
            <xs:complexType>
              <xs:all>
                <xs:element name="a"/>
                <xs:element name="b" minOccurs="0"/>
              </xs:all>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """)
    }

    @Test("an absent optional all-group is valid")
    func test_optionalAbsent() throws {
        #expect(try schema().validate("<opt/>").isEmpty)
    }

    @Test("a present optional all-group missing a required member is rejected")
    func test_optionalPresentIncomplete() throws {
        // 'a' is required once the group is present (c alone is not enough).
        #expect(try !schema().validate("<opt><c/></opt>").isEmpty)
        // 'c' is required too.
        #expect(try !schema().validate("<opt><a/></opt>").isEmpty)
    }

    @Test("a complete optional all-group is valid")
    func test_optionalPresentComplete() throws {
        #expect(try schema().validate("<opt><a/><c/></opt>").isEmpty)
        #expect(try schema().validate("<opt><a/><b/><c/></opt>").isEmpty)
    }

    @Test("a required all-group still enforces its members when empty")
    func test_requiredEmptyRejected() throws {
        #expect(try !schema().validate("<req/>").isEmpty) // 'a' required
        #expect(try schema().validate("<req><a/></req>").isEmpty)
    }
}
