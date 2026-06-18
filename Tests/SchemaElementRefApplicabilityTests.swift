import Testing
@testable import PureXML

@Suite("XSD element-ref applicability (src-element.2.2)")
struct SchemaElementRefApplicabilityTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func refParticle(_ refAttrs: String, inlineType: String = "") -> String {
        "<xs:element name=\"Main\" type=\"xs:string\"/>"
            + "<xs:element name=\"e\"><xs:complexType><xs:sequence>"
            + "<xs:element ref=\"Main\" \(refAttrs)>\(inlineType)</xs:element>"
            + "</xs:sequence></xs:complexType></xs:element>"
    }

    @Test("An element ref carrying a declaration-only attribute is rejected")
    func test_refDeclarationAttributesRejected() {
        for attr in ["nillable=\"true\"", "default=\"x\"", "fixed=\"x\"", "form=\"qualified\"", "block=\"#all\""] {
            #expect(!compiles(refParticle(attr)), "ref with \(attr) should be rejected")
        }
    }

    @Test("An element ref with an inline type is rejected")
    func test_refInlineTypeRejected() {
        #expect(!compiles(refParticle("", inlineType: "<xs:complexType><xs:sequence/></xs:complexType>")))
    }

    @Test("An element ref with only occurrence attributes compiles")
    func test_refOccurrenceAccepted() {
        #expect(compiles(refParticle("minOccurs=\"0\" maxOccurs=\"3\"")))
        #expect(compiles(refParticle("")))
    }
}
