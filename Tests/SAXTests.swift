@testable import PureXML
import Testing

@Suite("SAX")
struct SAXTests {
    @Test("Callbacks fire in document order, bracketed by start/end document")
    func test_order() throws {
        var log: [String] = []
        let handler = PureXML.Parsing.SAXHandler(
            startDocument: { log.append("start-doc") },
            endDocument: { log.append("end-doc") },
            startElement: { name, _ in log.append("start:\(name.localName)") },
            endElement: { name in log.append("end:\(name.localName)") },
            characters: { log.append("text:\($0)") },
        )
        try PureXML.parse("<a>hi<b/></a>", sax: handler)
        #expect(log == ["start-doc", "start:a", "text:hi", "start:b", "end:b", "end:a", "end-doc"])
    }

    @Test("CDATA, comments, and processing instructions are delivered")
    func test_miscNodes() throws {
        var kinds: [String] = []
        let handler = PureXML.Parsing.SAXHandler(
            cdata: { _ in kinds.append("cdata") },
            comment: { _ in kinds.append("comment") },
            processingInstruction: { _, _ in kinds.append("pi") },
        )
        try PureXML.parse("<r><![CDATA[x]]><!--c--><?pi go?></r>", sax: handler)
        #expect(kinds == ["cdata", "comment", "pi"])
    }

    @Test("Namespace URI is resolved on SAX callbacks")
    func test_namespace() throws {
        var uri: String?
        let handler = PureXML.Parsing.SAXHandler(startElement: { name, _ in
            if name.localName == "a" { uri = name.namespaceURI }
        })
        try PureXML.parse("<a xmlns=\"http://x\"/>", sax: handler)
        #expect(uri == "http://x")
    }

    @Test("A handler with no callbacks set parses without crashing")
    func test_emptyHandler() throws {
        try PureXML.parse("<a><b/>text</a>", sax: PureXML.Parsing.SAXHandler())
    }

    @Test("An empty document is an error")
    func test_emptyDocument() {
        #expect(throws: PureXML.Parsing.ParseError.emptyDocument) {
            try PureXML.parse("", sax: PureXML.Parsing.SAXHandler())
        }
    }
}
