import Testing
@testable import PureXML

@Suite("HTML")
struct HTMLTests {
    private func roundTrip(_ html: String) -> String {
        PureXML.HTML.serialize(PureXML.HTML.parse(html))
    }

    @Test("Void elements need no end tag and serialize without a slash")
    func test_voidElements() {
        #expect(roundTrip("<p>a<br>b<img src=\"x\">c</p>") == "<p>a<br>b<img src=\"x\">c</p>")
    }

    @Test("Optional end tags close implicitly")
    func test_optionalEndTags() {
        #expect(roundTrip("<ul><li>one<li>two</ul>") == "<ul><li>one</li><li>two</li></ul>")
        #expect(roundTrip("<p>first<p>second") == "<p>first</p><p>second</p>")
    }

    @Test("Table rows and cells close implicitly")
    func test_tableImpliedClose() {
        let html = "<table><tr><td>a<td>b<tr><td>c</table>"
        #expect(roundTrip(html) == "<table><tr><td>a</td><td>b</td></tr><tr><td>c</td></tr></table>")
    }

    @Test("Raw-text elements keep their content unescaped")
    func test_rawText() {
        let html = "<script>if (a < b && c > d) {}</script>"
        let parsed = PureXML.HTML.parse(html)
        #expect(PureXML.HTML.serialize(parsed) == html)
    }

    @Test("Attributes parse quoted, unquoted, and boolean forms")
    func test_attributes() {
        let parsed = PureXML.HTML.parse("<input type=text value='hi' disabled>")
        guard case let .document(children) = parsed, case let .element(element) = children.first else {
            Issue.record("expected an element")
            return
        }
        #expect(element.attributes.count == 3)
        #expect(element.attributes.contains { $0.name.description == "type" && $0.value == "text" })
        #expect(element.attributes.contains { $0.name.description == "disabled" && $0.value == "" })
    }

    @Test("Tag names are lowercased")
    func test_caseInsensitive() {
        #expect(roundTrip("<DIV><SPAN>x</SPAN></DIV>") == "<div><span>x</span></div>")
    }

    @Test("Character references are decoded and re-escaped")
    func test_entities() {
        #expect(roundTrip("<p>a &amp; b &lt; c &#65;</p>") == "<p>a &amp; b &lt; c A</p>")
        // Latin-1 characters re-encode to their HTML 4.01 names on output.
        #expect(roundTrip("<p>&nbsp;&copy;</p>") == "<p>&nbsp;&copy;</p>")
    }

    @Test("Comments and an unmatched end tag are handled leniently")
    func test_lenient() {
        #expect(roundTrip("<div><!-- note -->text</div>") == "<div><!-- note -->text</div>")
        #expect(roundTrip("<b>bold</i></b>") == "<b>bold</b>")
    }

    @Test("A representative document round-trips")
    func test_document() {
        let html = "<html><head><title>T</title></head>"
            + "<body><h1>Hi</h1><p>Para with <a href=\"/x\">link</a>.</p></body></html>"
        #expect(roundTrip(html) == html)
    }
}
