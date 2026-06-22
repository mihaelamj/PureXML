import Testing
@testable import PureXML

/// A defaulted or fixed `xs:IDREF`/`xs:IDREFS` attribute supplies its value when
/// the instance omits the attribute, so that value must still resolve to a
/// matching `xs:ID` (cvc-id). The reference was recorded only for present
/// attributes, so a dangling defaulted IDREF was wrongly accepted. Mirrors XSTS
/// idZ012.
@Suite("defaulted/fixed IDREF resolution")
struct SchemaIDREFDefaultTests {
    private func errors(_ xsd: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.Document(xsd).validate(xml)
    }

    private let defaultedIDREFS = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="root">
        <xs:complexType>
          <xs:attribute name="drefs" type="xs:IDREFS" default="abc"/>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    @Test("a defaulted IDREFS with no matching ID is rejected")
    func test_danglingDefaultedIDREFS() throws {
        #expect(try !errors(defaultedIDREFS, "<root/>").isEmpty)
    }

    private let resolvable = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="root">
        <xs:complexType>
          <xs:sequence>
            <xs:element name="t" maxOccurs="unbounded">
              <xs:complexType>
                <xs:attribute name="id" type="xs:ID"/>
                <xs:attribute name="dref" type="xs:IDREF" default="abc"/>
              </xs:complexType>
            </xs:element>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    @Test("a defaulted IDREF that resolves to a present ID stays valid")
    func test_resolvableDefaultedIDREF() throws {
        #expect(try errors(resolvable, #"<root><t id="abc"/></root>"#).isEmpty)
    }

    @Test("a present IDREF with no matching ID is still rejected (unchanged)")
    func test_danglingPresentIDREF() throws {
        #expect(try !errors(resolvable, #"<root><t dref="zzz"/></root>"#).isEmpty)
    }
}
