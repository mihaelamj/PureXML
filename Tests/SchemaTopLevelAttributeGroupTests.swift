@testable import PureXML
import Testing

@Suite("XSD top-level attributeGroup applicability (topLevelAttributeGroup)")
struct SchemaTopLevelAttributeGroupTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A top-level attributeGroup with ref is rejected")
    func test_topLevelForbiddenRejected() {
        #expect(!compiles("<xs:attributeGroup ref=\"g\"/>"))
    }

    @Test("A plain top-level attributeGroup declaration compiles")
    func test_plainTopLevelAccepted() {
        #expect(compiles("<xs:attributeGroup name=\"g\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:attributeGroup>"))
    }

    @Test("A local attributeGroup reference compiles")
    func test_localRefAccepted() {
        #expect(compiles(
            "<xs:attributeGroup name=\"g\"><xs:attribute name=\"a\" type=\"xs:string\"/></xs:attributeGroup>"
                + "<xs:element name=\"e\"><xs:complexType>"
                + "<xs:attributeGroup ref=\"g\"/>"
                + "</xs:complexType></xs:element>",
        ))
    }
}
