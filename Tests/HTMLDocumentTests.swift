import Testing
@testable import PureXML

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

    // MARK: Table tree construction

    /// Wraps a body fragment in the implied document structure for comparison.
    private func bodyDocument(_ inner: String) -> String {
        "<html><head></head><body>\(inner)</body></html>"
    }

    @Test("A bare table row gets an implied tbody")
    func test_impliedTbody() {
        #expect(document("<table><tr><td>x</td></tr></table>") == bodyDocument("<table><tbody><tr><td>x</td></tr></tbody></table>"))
    }

    @Test("A bare cell gets an implied tbody and row")
    func test_impliedRowAndSection() {
        #expect(document("<table><td>x</td></table>") == bodyDocument("<table><tbody><tr><td>x</td></tr></tbody></table>"))
    }

    @Test("An explicit section is not duplicated")
    func test_explicitSection() {
        #expect(document("<table><thead><tr><th>h</th></tr></thead></table>") == bodyDocument("<table><thead><tr><th>h</th></tr></thead></table>"))
    }

    @Test("Consecutive rows share one implied tbody")
    func test_consecutiveRows() {
        #expect(document("<table><tr><td>a</td><tr><td>b</td></table>") == bodyDocument("<table><tbody><tr><td>a</td></tr><tr><td>b</td></tr></tbody></table>"))
    }

    @Test("A stray element inside a table is foster-parented before it")
    func test_fosterElement() {
        #expect(document("<table><b>x</table>") == bodyDocument("<b>x</b><table></table>"))
    }

    @Test("Stray text inside a table is foster-parented before it")
    func test_fosterText() {
        #expect(document("<table>text<tr><td>c</td></tr></table>") == bodyDocument("text<table><tbody><tr><td>c</td></tr></tbody></table>"))
    }

    @Test("Well-formed cell content is not foster-parented")
    func test_noFosterInCell() {
        #expect(document("<table><tr><td><b>x</b></td></tr></table>") == bodyDocument("<table><tbody><tr><td><b>x</b></td></tr></tbody></table>"))
    }

    @Test("A template's content nests inside it")
    func test_templateContent() {
        #expect(document("<template><div>x</div></template>") == bodyDocument("<template><div>x</div></template>"))
    }
}
