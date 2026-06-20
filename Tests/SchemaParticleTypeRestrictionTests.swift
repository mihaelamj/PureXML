import Testing
@testable import PureXML

/// XSD 1.0 cos-particle-restrict NameAndTypeOK.2.2 (#158): when a complexContent
/// restriction narrows an element, the element's type must be validly derived from
/// the base element's type EXCLUDING extension (by restriction only). A type derived
/// from the base type by extension is not a valid restriction (corpus particlesIj008).
@Suite("XSD NameAndTypeOK restriction-only type derivation (#158)")
struct SchemaParticleTypeRestrictionTests {
    private func compiles(_ derivedC1Type: String) -> Bool {
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="foo"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:complexType name="barExt">
            <xs:complexContent><xs:extension base="foo"><xs:sequence><xs:element name="b" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
          </xs:complexType>
          <xs:complexType name="barRes">
            <xs:complexContent><xs:restriction base="foo"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:restriction></xs:complexContent>
          </xs:complexType>
          <xs:complexType name="B"><xs:sequence><xs:element name="c1" type="foo"/></xs:sequence></xs:complexType>
          <xs:complexType name="R">
            <xs:complexContent><xs:restriction base="B"><xs:sequence><xs:element name="c1" type="\(derivedC1Type)"/></xs:sequence></xs:restriction></xs:complexContent>
          </xs:complexType>
          <xs:element name="doc" type="R"/>
        </xs:schema>
        """
        return (try? PureXML.Schema.Document(schema)) != nil
    }

    @Test("restricting an element to a type derived by EXTENSION is rejected (particlesIj008)")
    func test_extensionDerivedTypeRejected() {
        #expect(!compiles("barExt"))
    }

    @Test("restricting an element to a type derived by RESTRICTION is accepted")
    func test_restrictionDerivedTypeAccepted() {
        #expect(compiles("barRes"))
    }

    @Test("restricting an element to the same type is accepted")
    func test_sameTypeAccepted() {
        #expect(compiles("foo"))
    }
}
