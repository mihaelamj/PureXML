import Testing
@testable import PureXML

@Suite("Writer")
struct WriterTests {
    @Test("Compact writing escapes content and round-trips through the parser")
    func test_compactRoundTrip() throws {
        var writer = PureXML.Emitting.Writer(options: .compact)
        writer.writeStartElement("catalog")
        writer.writeStartElement("book")
        writer.writeAttribute("id", "bk101")
        writer.writeString("A & B < C")
        writer.writeEndElement()
        writer.writeEndElement()
        let xml = writer.output
        #expect(xml == "<catalog><book id=\"bk101\">A &amp; B &lt; C</book></catalog>")

        let node = try PureXML.parse(xml)
        let book = node.firstElement?.children.first?.element
        #expect(book?.attributes.first?.value == "bk101")
        #expect(book?.text == "A & B < C")
    }

    @Test("Pretty writing indents element children, inlines text")
    func test_pretty() {
        var writer = PureXML.Emitting.Writer()
        writer.writeStartElement("book")
        writer.writeElement("title", text: "Guide")
        writer.writeEndElement()
        #expect(writer.output == "<book>\n  <title>Guide</title>\n</book>")
    }

    @Test("An empty element self-closes")
    func test_emptyElement() {
        var writer = PureXML.Emitting.Writer(options: .compact)
        writer.writeStartElement("br")
        writer.writeEndElement()
        #expect(writer.output == "<br/>")
    }

    @Test("CDATA, comments, and processing instructions are written")
    func test_miscNodes() {
        var writer = PureXML.Emitting.Writer(options: .compact)
        writer.writeStartElement("r")
        writer.writeCData("a<b")
        writer.writeComment("c")
        writer.writeProcessingInstruction(target: "pi", data: "go")
        writer.writeEndElement()
        #expect(writer.output == "<r><![CDATA[a<b]]><!--c--><?pi go?></r>")
    }

    @Test("Writer output matches the tree serializer for the same document")
    func test_parityWithSerializer() {
        let element = PureXML.Model.Element(
            "a",
            attributes: [.init("x", "1\n2")],
            children: [.element(.init("b", children: [.text("hi")]))],
        )
        let serialized = PureXML.serialize(.element(element), options: .compact)

        var writer = PureXML.Emitting.Writer(options: .compact)
        writer.writeStartElement("a")
        writer.writeAttribute("x", "1\n2")
        writer.writeStartElement("b")
        writer.writeString("hi")
        writer.writeEndElement()
        writer.writeEndElement()

        #expect(writer.output == serialized)
    }

    @Test("Misuse is forgiving: late attribute and unbalanced close are ignored")
    func test_forgiving() {
        var writer = PureXML.Emitting.Writer(options: .compact)
        writer.writeStartElement("a")
        writer.writeString("x")
        writer.writeAttribute("ignored", "y") // after content: ignored
        writer.writeEndElement()
        writer.writeEndElement() // unbalanced: ignored
        #expect(writer.output == "<a>x</a>")
    }
}

private extension PureXML.Model.Node {
    var firstElement: PureXML.Model.Element? {
        guard case let .document(children) = self else { return element }
        for child in children where child.element != nil {
            return child.element
        }
        return nil
    }
}
