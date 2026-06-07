@testable import PureXML
import Testing

@Suite("Model")
struct ModelTests {
    @Test("Qualified name splits a prefixed name")
    func test_qualifiedNameSplitsPrefix() {
        let name = PureXML.Model.QualifiedName("xs:element")
        #expect(name.prefix == "xs")
        #expect(name.localName == "element")
        #expect(name.description == "xs:element")
    }

    @Test("Qualified name keeps a bare name whole")
    func test_qualifiedNameKeepsBareName() {
        let name = PureXML.Model.QualifiedName("element")
        #expect(name.prefix == nil)
        #expect(name.localName == "element")
    }

    @Test("Element text concatenates text and CDATA children")
    func test_elementTextConcatenates() {
        let element = PureXML.Model.Element(
            "p",
            children: [.text("Hello "), .cdata("<world>")],
        )
        #expect(element.text == "Hello <world>")
    }
}
