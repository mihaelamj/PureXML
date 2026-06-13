@testable import PureXML
import Testing

/// An element with a `default` or `fixed` value takes that value when it appears
/// empty, so the empty content is valid even when the type would reject an empty
/// string (#147, XSTS valueConstraint set). Present content is still validated.
@Suite("Element default and fixed value constraints")
struct SchemaValueConstraintTests {
    private func element(_ constraint: String) throws -> PureXML.Schema.Document {
        try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v" type="xs:decimal" \(constraint)/>
        </xs:schema>
        """)
    }

    @Test("An empty element with a default takes the default and is valid")
    func test_defaultEmptyValid() throws {
        let doc = try element(#"default="12""#)
        #expect(try doc.validate("<v/>").isEmpty) // empty: default applies
        #expect(try doc.validate("<v>7</v>").isEmpty) // present valid decimal
        #expect(try !doc.validate("<v>abc</v>").isEmpty) // present content still validated
    }

    @Test("An empty element with a fixed value is valid; present content must equal it")
    func test_fixed() throws {
        let doc = try element(#"fixed="5""#)
        #expect(try doc.validate("<v/>").isEmpty) // empty: fixed applies
        #expect(try doc.validate("<v>5</v>").isEmpty) // equals fixed
        #expect(try !doc.validate("<v>6</v>").isEmpty) // differs from fixed
        #expect(try !doc.validate("<v>x</v>").isEmpty) // not even a decimal
    }

    @Test("An empty element's value constraint must still be valid against an xsi:type override")
    func test_constraintValueValidatedAgainstXsiType() throws {
        let doc = try PureXML.Schema.Document("""
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="v" type="B" fixed="a"/>
          <xs:simpleType name="B">
            <xs:restriction base="xs:string">
              <xs:enumeration value="a"/><xs:enumeration value="b"/>
            </xs:restriction>
          </xs:simpleType>
          <xs:simpleType name="D">
            <xs:restriction base="B"><xs:enumeration value="b"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """)
        // Empty: fixed 'a' is valid against the declared type B.
        #expect(try doc.validate("<v/>").isEmpty)
        // Empty under xsi:type=D: the fixed value 'a' is not in D's enumeration, so invalid.
        #expect(try !doc.validate(#"<v xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:type="D"/>"#).isEmpty)
    }
}
