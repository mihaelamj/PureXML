import PureXML
import Testing

/// Exercises the public entry points in `API.swift` that the rest of the suite
/// reaches only through subsystem types: the SAX and incremental-source parse
/// overloads, the streaming `events` overloads, and HTML content-model validation.
@Suite("Public entry points")
struct PublicEntryPointTests {
    private let xml = #"<r a="1"><c>hi</c></r>"#

    @Test("parse delivers SAX callbacks in document order")
    func test_parseSax() throws {
        var elements: [String] = []
        var text = ""
        let handler = PureXML.Parsing.SAXHandler(
            startElement: { name, _ in elements.append(name.localName) },
            characters: { text += $0 },
        )
        try PureXML.parse(xml, sax: handler)
        #expect(elements == ["r", "c"])
        #expect(text == "hi")
    }

    @Test("parse from an incremental byte source yields the same tree as the string parse")
    func test_parsePullingBytes() throws {
        var bytes = Array(xml.utf8)[...]
        let streamed = try PureXML.parse(pullingBytes: { bytes.isEmpty ? nil : bytes.removeFirst() })
        #expect(try PureXML.serialize(streamed) == PureXML.serialize(PureXML.parse(xml)))
    }

    @Test("every events overload streams the document to completion")
    func test_eventsOverloads() throws {
        var fromBytes = try PureXML.events(bytes: Array(xml.utf8))
        var byteEvents = 0
        while try fromBytes.next() != nil {
            byteEvents += 1
        }
        #expect(byteEvents > 0)

        var chars = Array(xml)[...]
        var fromChars = PureXML.events(pulling: { chars.isEmpty ? nil : chars.removeFirst() })
        var charEvents = 0
        while try fromChars.next() != nil {
            charEvents += 1
        }
        #expect(charEvents == byteEvents)

        var sourceBytes = Array(xml.utf8)[...]
        var fromPulledBytes = PureXML.events(pullingBytes: { sourceBytes.isEmpty ? nil : sourceBytes.removeFirst() })
        var pulledByteEvents = 0
        while try fromPulledBytes.next() != nil {
            pulledByteEvents += 1
        }
        #expect(pulledByteEvents == byteEvents)
    }

    @Test("validateHTML flags a duplicate id")
    func test_validateHTML() throws {
        let duplicate = try PureXML.parse(#"<root><a id="d"></a><b id="d"></b></root>"#)
        #expect(!PureXML.validateHTML(duplicate).isEmpty)
        let unique = try PureXML.parse(#"<root><a id="d"></a><b id="e"></b></root>"#)
        #expect(PureXML.validateHTML(unique).allSatisfy { !$0.reason.lowercased().contains("id") })
    }
}
