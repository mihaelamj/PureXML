import Testing
@testable import PureXML

/// derivation-ok-restriction.2 for simpleContent: a complex type with simple
/// content that restricts a base may not relax a base `required` attribute to
/// `optional`. The attribute-use restriction check previously ran only over
/// `complexContent` restrictions, so a `simpleContent` restriction that relaxed a
/// required attribute was wrongly accepted (XSTS particlesZ030_d, which libxml2
/// also rejects). Corpus-free pin of the rule.
@Suite("simpleContent attribute-use restriction")
struct SimpleContentAttrRestrictionTests {
    private func compiles(_ schema: String) -> Bool {
        (try? PureXML.Schema.Document(schema)) != nil
    }

    private func schema(derivedUse: String) -> String {
        """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema">
          <xsd:complexType name="base">
            <xsd:simpleContent>
              <xsd:extension base="xsd:string">
                <xsd:attribute name="a" use="required"/>
              </xsd:extension>
            </xsd:simpleContent>
          </xsd:complexType>
          <xsd:complexType name="derived">
            <xsd:simpleContent>
              <xsd:restriction base="base">
                <xsd:attribute name="a" use="\(derivedUse)"/>
              </xsd:restriction>
            </xsd:simpleContent>
          </xsd:complexType>
        </xsd:schema>
        """
    }

    @Test("a simpleContent restriction may not relax a required attribute to optional")
    func test_requiredToOptionalRejected() {
        #expect(!compiles(schema(derivedUse: "optional")))
    }

    @Test("a simpleContent restriction that keeps the attribute required compiles")
    func test_requiredKeptAccepted() {
        #expect(compiles(schema(derivedUse: "required")))
    }
}
