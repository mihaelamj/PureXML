@testable import PureXML
import Testing

@Suite("Serialization options: quotes, line endings, xml:space, writer NS")
struct SerializationOptionsTests {
    private func serialize(_ xml: String, _ options: PureXML.Emitting.Options) throws -> String {
        let node = try PureXML.parse(xml)
        return PureXML.serialize(node, options: options)
    }

    @Test("Single-quote attribute style delimits with apostrophes")
    func test_singleQuote() throws {
        let options = PureXML.Emitting.Options(prettyPrint: false, attributeQuote: .single)
        #expect(try serialize("<a id=\"1\"/>", options) == "<a id='1'/>")
    }

    @Test("A quote of the active style inside a value is escaped")
    func test_quoteEscaping() throws {
        let single = PureXML.Emitting.Options(prettyPrint: false, attributeQuote: .single)
        // An apostrophe in the value is escaped; a double quote is left literal.
        #expect(try serialize("<a t=\"it&apos;s &quot;x&quot;\"/>", single) == "<a t='it&apos;s \"x\"'/>")
    }

    @Test("Line ending option controls inserted newlines")
    func test_lineEnding() throws {
        let options = PureXML.Emitting.Options(indent: "  ", lineEnding: "\r\n")
        let output = try serialize("<a><b/></a>", options)
        #expect(output.contains("\r\n"))
        #expect(!output.contains("\n\n"))
    }

    @Test("xml:space=preserve suppresses pretty-print indentation in the subtree")
    func test_xmlSpacePreserve() throws {
        let xml = "<a xml:space=\"preserve\"><b><c/></b></a>"
        let output = try serialize(xml, .default)
        // No indentation inserted inside the preserved element.
        #expect(output == "<a xml:space=\"preserve\"><b><c/></b></a>\n")
    }

    @Test("Without xml:space, pretty-print indents as usual")
    func test_prettyPrintDefault() throws {
        let output = try serialize("<a><b><c/></b></a>", .default)
        #expect(output.contains("\n  <b>"))
    }

    @Test("Writer namespace methods emit a qualified name and an xmlns declaration")
    func test_writerNamespace() {
        var writer = PureXML.Emitting.Writer(options: PureXML.Emitting.Options(prettyPrint: false))
        writer.writeStartElementNS(prefix: "x", localName: "a", namespaceURI: "urn:x")
        writer.writeString("hi")
        writer.writeEndElement()
        #expect(writer.output == "<x:a xmlns:x=\"urn:x\">hi</x:a>")
    }

    @Test("Writer writes a default-namespace declaration for a nil prefix")
    func test_writerDefaultNamespace() {
        var writer = PureXML.Emitting.Writer(options: PureXML.Emitting.Options(prettyPrint: false))
        writer.writeStartElementNS(prefix: nil, localName: "a", namespaceURI: "urn:d")
        writer.writeEndElement()
        #expect(writer.output == "<a xmlns=\"urn:d\"/>")
    }
}
