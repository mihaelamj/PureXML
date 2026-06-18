import Testing
@testable import PureXML

@Suite("Parsing")
struct ParsingTests {
    @Test("Empty input reports an empty document")
    func test_emptyInputThrows() {
        #expect(throws: PureXML.Parsing.ParseError.emptyDocument) {
            try PureXML.parse("")
        }
    }

    @Test("Parses an empty element")
    func test_parsesEmptyElement() throws {
        let node = try PureXML.parse("<root/>")
        guard case let .document(children) = node else {
            Issue.record("expected a document node")
            return
        }
        #expect(children == [.element(.init("root"))])
    }

    @Test("Parses attributes, decoding entities")
    func test_parsesAttributes() throws {
        let node = try PureXML.parse("<a href=\"x?b=1&amp;c=2\" id='bk1'/>")
        let element = node.firstElement
        #expect(element?.attributes == [.init("href", "x?b=1&c=2"), .init("id", "bk1")])
    }

    @Test("Parses nested elements and text with entities")
    func test_parsesNestedAndText() throws {
        let node = try PureXML.parse("<p>1 &lt; 2 &amp; ok<b>x</b></p>")
        let paragraph = node.firstElement
        #expect(paragraph?.name.localName == "p")
        #expect(paragraph?.children.first == .text("1 < 2 & ok"))
        #expect(paragraph?.children.last == .element(.init("b", children: [.text("x")])))
    }

    @Test("Parses comments, CDATA, and processing instructions")
    func test_parsesMiscNodes() throws {
        let node = try PureXML.parse("<r><!--c--><![CDATA[a<b]]><?pi go?></r>")
        let root = node.firstElement
        #expect(root?.children == [
            .comment("c"),
            .cdata("a<b"),
            .processingInstruction(target: "pi", data: "go"),
        ])
    }

    @Test("Skips an XML declaration in the prolog")
    func test_skipsXMLDeclaration() throws {
        let node = try PureXML.parse("<?xml version=\"1.0\"?>\n<root>hi</root>")
        #expect(node.firstElement?.text == "hi")
    }

    @Test("Round-trips through the serializer")
    func test_roundTripsSerializerOutput() throws {
        let original = PureXML.Model.Element(
            "catalog",
            children: [.element(.init("book", attributes: [.init("id", "bk101")], children: [.text("A & B")]))],
        )
        let xml = PureXML.serialize(.element(original), options: .compact)
        let reparsed = try PureXML.parse(xml)
        #expect(reparsed.firstElement == original)
    }

    @Test("Mismatched end tag is an error")
    func test_mismatchedEndTagThrows() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a></b>")
        }
    }

    @Test("DOCTYPE is rejected by default (security posture)")
    func test_doctypeRejected() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<!DOCTYPE a><a/>")
        }
    }

    @Test("Unterminated tag is an error")
    func test_unterminatedTagThrows() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a><b></a>")
        }
    }

    @Test("Nesting beyond the depth limit is rejected")
    func test_depthLimitRejected() {
        let limits = PureXML.Parsing.Limits(maxDepth: 3)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a><b><c><d>x</d></c></b></a>", limits: limits)
        }
    }

    @Test("Nesting within the depth limit parses")
    func test_depthWithinLimit() throws {
        let limits = PureXML.Parsing.Limits(maxDepth: 5)
        let node = try PureXML.parse("<a><b><c>x</c></b></a>", limits: limits)
        #expect(node.firstElement?.name.localName == "a")
    }

    @Test("Names over the length limit are rejected")
    func test_nameLimitRejected() {
        let limits = PureXML.Parsing.Limits(maxNameLength: 4)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<abcdefgh/>", limits: limits)
        }
    }

    @Test("Content over the length limit is rejected")
    func test_contentLimitRejected() {
        let limits = PureXML.Parsing.Limits(maxContentLength: 5)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a>abcdefghij</a>", limits: limits)
        }
    }

    @Test("Streams events one at a time without building a tree")
    func test_streamsEvents() throws {
        var reader = PureXML.events("<r a=\"1\">hi<b/></r>")
        var events: [PureXML.Parsing.Event] = []
        while let event = try reader.next() {
            events.append(event)
        }
        #expect(events == [
            .startElement(name: .init("r"), attributes: [.init("a", "1")]),
            .characters("hi"),
            .startElement(name: .init("b"), attributes: []),
            .endElement(name: .init("b")),
            .endElement(name: .init("r")),
        ])
    }

    /// Proves the parser does not require the whole string at once: the source is
    /// a closure pulling characters across separate chunks, never joined.
    @Test("Parses from an incremental, chunked character source")
    func test_parsesFromChunkedSource() throws {
        let chunks = ["<ro", "ot a", "=", "'1'>", "te", "xt<c/>", "</roo", "t>"]
        var chunkIterator = chunks.makeIterator()
        var charIterator = (chunkIterator.next() ?? "").makeIterator()
        let pull: () -> Character? = {
            while true {
                if let character = charIterator.next() {
                    return character
                }
                guard let nextChunk = chunkIterator.next() else {
                    return nil
                }
                charIterator = nextChunk.makeIterator()
            }
        }

        let node = try PureXML.parse(pulling: pull)
        let root = node.firstElement
        #expect(root?.name.localName == "root")
        #expect(root?.attributes == [.init("a", "1")])
        #expect(root?.children.first == .text("text"))
        #expect(root?.children.last == .element(.init("c")))
    }

    @Test("A CDATA close in content is rejected when it straddles the bulk-scan boundary")
    func test_cdataCloseAcrossScanBoundary() throws {
        // The fast byte path never holds ']' bytes, so the "]]" lands in the
        // character path and the following '>' must not begin a bulk run
        // (W3C ibm14n01, caught by the conformance suite).
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<s>My name is Snow ]]> Man</s>")
        }
        // A lone '>' after plain text stays legal content.
        let document = try PureXML.parse("<s>a > b</s>")
        let serialized = PureXML.serialize(document)
        #expect(serialized.contains("a &gt; b"))
    }
}

private extension PureXML.Model.Node {
    var firstElement: PureXML.Model.Element? {
        guard case let .document(children) = self else { return element }
        for child in children {
            if case let .element(element) = child { return element }
        }
        return nil
    }
}
