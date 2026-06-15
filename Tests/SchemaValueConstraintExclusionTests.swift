@testable import PureXML
import Testing

@Suite("XSD default/fixed value-constraint mutual exclusion (src-element.1 / src-attribute.1)")
struct SchemaValueConstraintExclusionTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("An element with both default and fixed is rejected")
    func test_elementBothRejected() {
        #expect(!compiles("<xs:element name=\"e\" type=\"xs:string\" default=\"0\" fixed=\"0\"/>"))
    }

    @Test("An attribute with both default and fixed is rejected")
    func test_attributeBothRejected() {
        #expect(!compiles(
            "<xs:element name=\"e\"><xs:complexType>"
                + "<xs:attribute name=\"a\" type=\"xs:string\" default=\"x\" fixed=\"x\"/>"
                + "</xs:complexType></xs:element>",
        ))
    }

    @Test("An element or attribute with only one of default/fixed compiles")
    func test_onlyOneAccepted() {
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\" default=\"0\"/>"))
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\" fixed=\"0\"/>"))
        #expect(compiles("<xs:element name=\"e\" type=\"xs:string\"/>"))
    }
}
