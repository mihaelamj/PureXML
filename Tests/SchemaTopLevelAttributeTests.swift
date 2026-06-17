@testable import PureXML
import Testing

@Suite("XSD top-level attribute applicability (topLevelAttribute)")
struct SchemaTopLevelAttributeTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A top-level attribute with use is rejected")
    func test_topLevelUseRejected() {
        #expect(!compiles("<xs:attribute name=\"a\" type=\"xs:string\" use=\"required\"/>"))
        #expect(!compiles("<xs:attribute name=\"a\" type=\"xs:string\" use=\"optional\"/>"))
        #expect(!compiles("<xs:attribute name=\"a\" type=\"xs:string\" use=\"prohibited\"/>"))
    }

    @Test("A top-level attribute with form is rejected")
    func test_topLevelFormRejected() {
        #expect(!compiles("<xs:attribute name=\"a\" type=\"xs:string\" form=\"qualified\"/>"))
    }

    @Test("A plain top-level attribute declaration compiles")
    func test_plainTopLevelAccepted() {
        #expect(compiles("<xs:attribute name=\"a\" type=\"xs:string\"/>"))
        #expect(compiles("<xs:attribute name=\"a\" type=\"xs:string\" default=\"x\"/>"))
    }

    /// `use`, `form`, and a `ref` are legitimate on a LOCAL attribute use inside a
    /// complex type; the rule applies only to top-level declarations.
    @Test("A local attribute use with use/form compiles")
    func test_localUseAccepted() {
        #expect(compiles(
            "<xs:element name=\"e\"><xs:complexType>"
                + "<xs:attribute name=\"a\" type=\"xs:string\" use=\"required\" form=\"qualified\"/>"
                + "</xs:complexType></xs:element>",
        ))
        // A local ref with use is fine.
        #expect(compiles(
            "<xs:attribute name=\"g\" type=\"xs:string\"/>"
                + "<xs:element name=\"e\"><xs:complexType>"
                + "<xs:attribute ref=\"g\" use=\"required\"/>"
                + "</xs:complexType></xs:element>",
        ))
    }

    /// au-props-correct: an attribute's type must be a simple type. A complex type
    /// (here one with simple content) is rejected; a built-in or user simple type,
    /// an inline simpleType, or no type (anySimpleType) is valid.
    @Test("an attribute's type must be a simple type")
    func test_attributeTypeMustBeSimple() {
        let complexT = "<xs:complexType name=\"ct\"><xs:simpleContent><xs:extension base=\"xs:integer\"/></xs:simpleContent></xs:complexType>"
        #expect(!compiles(complexT + "<xs:attribute name=\"a\" type=\"ct\"/>"))
        #expect(!compiles("<xs:attribute name=\"a\" type=\"xs:anyType\"/>"))
        let simpleT = "<xs:simpleType name=\"st\"><xs:restriction base=\"xs:string\"/></xs:simpleType>"
        #expect(compiles(simpleT + "<xs:attribute name=\"a\" type=\"st\"/>"))
        #expect(compiles("<xs:attribute name=\"a\"><xs:simpleType><xs:restriction base=\"xs:string\"/></xs:simpleType></xs:attribute>"))
        #expect(compiles("<xs:attribute name=\"a\"/>"))
    }
}
