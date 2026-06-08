@testable import PureXML
import Testing

@Suite("HTML5 document tree construction")
struct HTMLDocumentTests {
    private func document(_ html: String) -> String {
        PureXML.HTML.serialize(PureXML.HTML.parseDocument(html))
    }

    @Test("Implied html, head, and body wrap a bare fragment")
    func test_impliedStructure() {
        #expect(document("<p>hello</p>") == "<html><head></head><body><p>hello</p></body></html>")
    }

    @Test("Head-only elements are routed into the head")
    func test_headRouting() {
        let html = "<title>T</title><meta charset=\"utf-8\"><p>body</p>"
        let expected = "<html><head><title>T</title><meta charset=\"utf-8\"></head><body><p>body</p></body></html>"
        #expect(document(html) == expected)
    }

    @Test("Explicit html, head, and body are honored")
    func test_explicitStructure() {
        let html = "<html><head><title>T</title></head><body><h1>Hi</h1></body></html>"
        #expect(document(html) == "<html><head><title>T</title></head><body><h1>Hi</h1></body></html>")
    }

    @Test("Flow content before any head element starts the body")
    func test_flowStartsBody() {
        #expect(document("<div>x</div>") == "<html><head></head><body><div>x</div></body></html>")
    }

    @Test("A head element after body content stays in the body's flow")
    func test_explicitBodyThenContent() {
        let html = "<body><p>one</p><p>two</p></body>"
        #expect(document(html) == "<html><head></head><body><p>one</p><p>two</p></body></html>")
    }

    @Test("html attributes are preserved on the implied structure")
    func test_htmlAttributes() {
        #expect(document("<html lang=\"en\"><p>x</p></html>") == "<html lang=\"en\"><head></head><body><p>x</p></body></html>")
    }
}
