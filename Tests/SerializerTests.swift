@testable import PureXML
import Testing

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

    @Test("Pretty printing indents nested elements")
    func test_prettyPrintsNested() {
        let inner = PureXML.Model.Element("title", children: [.text("Guide")])
        let outer = PureXML.Model.Element("book", children: [.element(inner)])
        let xml = PureXML.serialize(.element(outer))
        #expect(xml == "<book>\n  <title>Guide</title>\n</book>\n")
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
