import Testing
@testable import PureXML

/// Locks the pull and push tokenizers together (#115): EventReader and the
/// resumable PushScanner implement the XML token grammar twice, so the same
/// document must yield the same event stream through both, even when the push
/// side is fed one character at a time.
@Suite("Pull vs push tokenizer differential")
struct PullPushDifferentialTests {
    private final class EventLog {
        var events: [PureXML.Parsing.Event] = []
    }

    private func pullEvents(_ xml: String) throws -> [PureXML.Parsing.Event] {
        var reader = PureXML.events(xml)
        var events: [PureXML.Parsing.Event] = []
        while let event = try reader.next() {
            events.append(event)
        }
        return events
    }

    private func pushEvents(_ xml: String) throws -> [PureXML.Parsing.Event] {
        let log = EventLog()
        let sax = PureXML.Parsing.SAXHandler(
            startElement: { log.events.append(.startElement(name: $0, attributes: $1)) },
            endElement: { log.events.append(.endElement(name: $0)) },
            characters: { log.events.append(.characters($0)) },
            cdata: { log.events.append(.cdata($0)) },
            comment: { log.events.append(.comment($0)) },
            processingInstruction: { log.events.append(.processingInstruction(target: $0, data: $1)) },
        )
        var parser = PureXML.Parsing.PushParser(sax: sax)
        // One character per feed: the resumability worst case.
        for character in xml {
            try parser.feed(String(character))
        }
        try parser.finish()
        return log.events
    }

    /// Adjacent character events merge, so chunk boundaries (which legitimately
    /// split text) do not count as divergence.
    private func coalesced(_ events: [PureXML.Parsing.Event]) -> [PureXML.Parsing.Event] {
        var result: [PureXML.Parsing.Event] = []
        for event in events {
            if case let .characters(tail) = event, case let .characters(head)? = result.last {
                result[result.count - 1] = .characters(head + tail)
            } else {
                result.append(event)
            }
        }
        return result
    }

    @Test("Both tokenizers yield the same event stream, even fed one character at a time")
    func test_eventStreamsAgree() throws {
        let corpus = [
            "<r>hi</r>",
            "<r><a x=\"1\" y='2'/><b>t</b></r>",
            "<p>text <b>bold</b> tail</p>",
            "<r><!-- note --><![CDATA[<raw>&]]><?pi data?></r>",
            "<r>&amp;&lt;&#65;</r>",
            "<r xmlns:p=\"urn:x\"><p:c p:a=\"v\"/></r>",
            "<r>\n  <a/>\n  <b/>\n</r>",
            "<a><b><c>deep</c></b></a>",
        ]
        for document in corpus {
            let pull = try coalesced(pullEvents(document))
            let push = try coalesced(pushEvents(document))
            #expect(pull == push, "tokenizers diverged for: \(document)\n  pull: \(pull)\n  push: \(push)")
        }
    }
}
