import Testing
@testable import PureXML

/// XSD 1.0 `cos-ct-restricts`: complexContent restriction mixedness is
/// one-directional. A restriction may keep mixedness or narrow mixed to
/// element-only, but must not add mixed content to an element-only base. This pins
/// the asymmetry the #184 guard schemas (addB064, addB150, ctZ010h, particlesL012)
/// depend on: a bidirectional "derived mixed must equal base mixed" rule would
/// wrongly reject the legal narrowing direction (it regressed four valid schemas
/// when tried). The targets ctZ010d (extension) and ctZ010e (restriction) are
/// already rejected by `extensionMixedAgreementErrors` and `ParticleRestriction`
/// respectively; this guards the restriction half from regressing.
@Suite("XSD restriction mixed-content asymmetry (#184)")
struct SchemaRestrictionMixedTests {
    private func document(baseMixed: Bool, derivedMixed: Bool?) -> String {
        let baseAttr = baseMixed ? " mixed=\"true\"" : ""
        let derivedAttr = derivedMixed.map { " mixed=\"\($0)\"" } ?? ""
        return """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="base"\(baseAttr)>
            <xs:sequence><xs:element name="bar" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="der"\(derivedAttr)>
            <xs:complexContent>
              <xs:restriction base="base">
                <xs:sequence><xs:element name="bar" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="e" type="der"/>
        </xs:schema>
        """
    }

    private func compiles(baseMixed: Bool, derivedMixed: Bool?) -> Bool {
        (try? PureXML.Schema.Document(document(baseMixed: baseMixed, derivedMixed: derivedMixed))) != nil
    }

    @Test("ctZ010e: a mixed restriction of an element-only base adds mixedness and is rejected")
    func test_addingMixedRejected() {
        #expect(!compiles(baseMixed: false, derivedMixed: true))
    }

    @Test("ctZ010h: a non-mixed or omitted restriction of a mixed base narrows mixedness and is valid")
    func test_narrowingMixedValid() {
        #expect(compiles(baseMixed: true, derivedMixed: false))
        #expect(compiles(baseMixed: true, derivedMixed: nil))
    }

    @Test("Keeping the base mixedness in either state is valid")
    func test_keepingMixedValid() {
        #expect(compiles(baseMixed: true, derivedMixed: true))
        #expect(compiles(baseMixed: false, derivedMixed: false))
    }
}
