@testable import PureXML
import Testing

@Suite("XSD top-level element applicability (topLevelElement)")
struct SchemaTopLevelElementTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A top-level element with ref/form/minOccurs/maxOccurs is rejected")
    func test_topLevelForbiddenRejected() {
        #expect(!compiles("<xs:element name=\"g\" type=\"xs:string\"/><xs:element ref=\"g\"/>"))
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\" form=\"qualified\"/>"))
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\" minOccurs=\"0\"/>"))
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\" maxOccurs=\"3\"/>"))
    }

    @Test("A plain top-level element declaration compiles")
    func test_plainTopLevelAccepted() {
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\"/>"))
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\" nillable=\"true\" abstract=\"true\"/>"))
    }

    /// `ref`, `minOccurs`, and `maxOccurs` are legitimate on a LOCAL element
    /// particle inside a complex type; the rule applies only to top-level
    /// declarations.
    @Test("A local element ref with occurrence compiles")
    func test_localParticleAccepted() {
        #expect(compiles(
            "<xs:element name=\"g\" type=\"xs:string\"/>"
                + "<xs:element name=\"e\"><xs:complexType><xs:sequence>"
                + "<xs:element ref=\"g\" minOccurs=\"0\" maxOccurs=\"3\"/>"
                + "</xs:sequence></xs:complexType></xs:element>",
        ))
    }
}
