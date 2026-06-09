@testable import PureXML
import Testing

@Suite("HTML5 foreign content (SVG/MathML namespaces)")
struct HTMLForeignContentTests {
    private let svg = "http://www.w3.org/2000/svg"
    private let mathml = "http://www.w3.org/1998/Math/MathML"

    /// The first element with the given local name in the parsed document.
    private func find(_ name: String, in html: String) -> PureXML.Model.Element? {
        find(name, in: PureXML.HTML.parseDocument(html))
    }

    private func find(_ name: String, in node: PureXML.Model.Node) -> PureXML.Model.Element? {
        switch node {
        case let .document(children):
            return children.lazy.compactMap { find(name, in: $0) }.first
        case let .element(element):
            if element.name.localName == name { return element }
            return element.children.lazy.compactMap { find(name, in: $0) }.first
        default:
            return nil
        }
    }

    @Test("An svg element and its descendants carry the SVG namespace")
    func test_svgNamespace() {
        let html = "<p><svg><g><rect></rect></g></svg></p>"
        #expect(find("svg", in: html)?.name.namespaceURI == svg)
        #expect(find("g", in: html)?.name.namespaceURI == svg)
        #expect(find("rect", in: html)?.name.namespaceURI == svg)
    }

    @Test("A math element and its descendants carry the MathML namespace")
    func test_mathmlNamespace() {
        let html = "<math><mi>x</mi></math>"
        #expect(find("math", in: html)?.name.namespaceURI == mathml)
        #expect(find("mi", in: html)?.name.namespaceURI == mathml)
    }

    @Test("Ordinary HTML elements have no namespace")
    func test_htmlNoNamespace() {
        #expect(find("p", in: "<p>text</p>")?.name.namespaceURI == nil)
    }

    @Test("HTML content after a closed svg is back in no namespace")
    func test_namespaceResumes() {
        let html = "<svg><rect></rect></svg><p>after</p>"
        #expect(find("rect", in: html)?.name.namespaceURI == svg)
        #expect(find("p", in: html)?.name.namespaceURI == nil)
    }
}
