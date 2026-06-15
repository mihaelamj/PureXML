@testable import PureXML
import Testing

@Suite("XSD attribute default requires use=optional (src-attribute.2)")
struct SchemaAttributeDefaultUseTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func attribute(_ attrs: String) -> String {
        "<xs:element name=\"e\"><xs:complexType>"
            + "<xs:attribute name=\"a\" type=\"xs:string\" \(attrs)/>"
            + "</xs:complexType></xs:element>"
    }

    @Test("A default with use=required is rejected")
    func test_defaultRequiredRejected() {
        #expect(!compiles(attribute("default=\"x\" use=\"required\"")))
    }

    @Test("A default with use=prohibited is rejected")
    func test_defaultProhibitedRejected() {
        #expect(!compiles(attribute("default=\"x\" use=\"prohibited\"")))
    }

    @Test("A default with use=optional, or with no use, compiles")
    func test_defaultOptionalAccepted() {
        #expect(compiles(attribute("default=\"x\" use=\"optional\"")))
        #expect(compiles(attribute("default=\"x\"")))
    }

    /// `src-attribute.2` constrains only `default`; a `fixed` with `use="required"`
    /// is a valid required-with-fixed-value attribute and must compile.
    @Test("A fixed with use=required compiles (the rule is about default only)")
    func test_fixedRequiredAccepted() {
        #expect(compiles(attribute("fixed=\"x\" use=\"required\"")))
    }
}
