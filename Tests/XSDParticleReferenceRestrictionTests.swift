import Testing
@testable import PureXML

@Suite("XSD Particle Restriction References")
struct XSDParticleReferenceRestrictionTests {
    @Test("NameAndTypeOK: element refs keep the global declaration's type")
    func test_globalRefCarriesTypeMetadata() {
        let invalid = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="c" type="xs:decimal"/>
          <xs:complexType name="B"><xs:choice><xs:element ref="c"/></xs:choice></xs:complexType>
          <xs:complexType name="R"><xs:complexContent><xs:restriction base="B">
            <xs:choice><xs:element name="c"/></xs:choice>
          </xs:restriction></xs:complexContent></xs:complexType>
        </xs:schema>
        """
        #expect((try? PureXML.Schema.Document(invalid)) == nil)

        let valid = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="c" type="xs:decimal"/>
          <xs:complexType name="B"><xs:choice><xs:element ref="c"/></xs:choice></xs:complexType>
          <xs:complexType name="R"><xs:complexContent><xs:restriction base="B">
            <xs:choice><xs:element name="c" type="xs:short"/></xs:choice>
          </xs:restriction></xs:complexContent></xs:complexType>
        </xs:schema>
        """
        #expect((try? PureXML.Schema.Document(valid)) != nil)
    }
}
