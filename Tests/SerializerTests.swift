import Testing
@testable import PureXML

@Suite("Serializer")
struct SerializerTests {
    @Test("Empty element self-closes")
    func test_emptyElementSelfCloses() {
        let node = PureXML.Model.Node.element(.init("br"))
        #expect(PureXML.serialize(node, options: .compact) == "<br/>")
    }

    @Test("Attributes and text are escaped")
    func test_escapesAttributesAndText() {
        let element = PureXML.Model.Element(
            "a",
            attributes: [.init("href", "x?b=1&c=2")],
            children: [.text("1 < 2")],
        )
        let xml = PureXML.serialize(.element(element), options: .compact)
        #expect(xml == "<a href=\"x?b=1&amp;c=2\">1 &lt; 2</a>")
    }

    @Test("Attribute whitespace is escaped as numeric character references")
    func test_escapesAttributeWhitespace() {
        // libxml2 escapes tab/newline/CR in attribute values so they survive a
        // spec-compliant parser's attribute-value normalization.
        let element = PureXML.Model.Element("a", attributes: [.init("x", "1\t2\n3\r4>5")])
        let xml = PureXML.serialize(.element(element), options: .compact)
        #expect(xml == "<a x=\"1&#9;2&#10;3&#13;4&gt;5\"/>")
    }

    @Test("Pretty printing indents nested elements")
    func test_prettyPrintsNested() {
        let inner = PureXML.Model.Element("title", children: [.text("Guide")])
        let outer = PureXML.Model.Element("book", children: [.element(inner)])
        let xml = PureXML.serialize(.element(outer))
        #expect(xml == "<book>\n  <title>Guide</title>\n</book>\n")
    }

    @Test("Mixed content is emitted inline, not reformatted")
    func test_mixedContentStaysInline() {
        // Pretty-printing must not inject whitespace around text in mixed content.
        let element = PureXML.Model.Element(
            "p",
            children: [.text("hi "), .element(.init("b", children: [.text("x")])), .text(" bye")],
        )
        let xml = PureXML.serialize(.element(element))
        #expect(xml == "<p>hi <b>x</b> bye</p>\n")
    }

    @Test("Nested trees serialize iteratively and correctly")
    func test_nestedSerializesCorrectly() {
        // The serializer uses an explicit work stack (not recursion), so it is
        // not the depth bottleneck. The remaining ceiling is the recursive
        // Model.Node value itself, which is why the parser caps nesting depth.
        var node = PureXML.Model.Node.text("leaf")
        for _ in 0 ..< 200 {
            node = .element(.init("n", children: [node]))
        }
        let xml = PureXML.serialize(node, options: .compact)
        #expect(xml.hasPrefix("<n><n>"))
        #expect(xml.hasSuffix("</n></n>"))
        #expect(xml.contains("<n>leaf</n>"))
    }

    @Test("CDATA and comments round-trip verbatim")
    func test_emitsCDATAAndComments() {
        #expect(PureXML.serialize(.cdata("a<b")) == "<![CDATA[a<b]]>")
        #expect(PureXML.serialize(.comment(" note ")) == "<!-- note -->")
        #expect(
            PureXML.serialize(.processingInstruction(target: "xml-stylesheet", data: "href=\"s.css\""))
                == "<?xml-stylesheet href=\"s.css\"?>",
        )
    }
}
