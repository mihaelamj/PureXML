@testable import PureXML
import Testing

@Suite("Push parser")
struct PushParserTests {
    /// Feeds the chunks through a push parser and returns a flat list of event
    /// descriptions.
    private func collect(_ chunks: [String]) throws -> [String] {
        var events: [String] = []
        let handler = PureXML.Parsing.SAXHandler(
            startElement: { name, attributes in
                let attrs = attributes.map { " \($0.name.description)=\($0.value)" }.joined()
                events.append("start:\(name.description)\(attrs)")
            },
            endElement: { events.append("end:\($0.description)") },
            characters: { events.append("text:\($0)") },
            cdata: { events.append("cdata:\($0)") },
            comment: { events.append("comment:\($0)") },
            processingInstruction: { events.append("pi:\($0):\($1)") },
        )
        var parser = PureXML.Parsing.PushParser(sax: handler)
        for chunk in chunks {
            try parser.feed(chunk)
        }
        try parser.finish()
        return events
    }

    private let document = "<root a=\"1\" xmlns:n=\"urn:x\">"
        + "<n:b>hi &amp; bye</n:b><!-- c --><![CDATA[x<y]]><?pi data?><self/>tail</root>"

    @Test("A whole document produces the expected events")
    func test_whole() throws {
        #expect(try collect([document]) == [
            "start:root a=1 xmlns:n=urn:x",
            "start:n:b",
            "text:hi & bye",
            "end:n:b",
            "comment: c ",
            "cdata:x<y",
            "pi:pi:data",
            "start:self",
            "end:self",
            "text:tail",
            "end:root",
        ])
    }

    @Test("Splitting at every boundary yields identical events")
    func test_everyBoundary() throws {
        let whole = try collect([document])
        let characters = Array(document)
        for cut in 0 ... characters.count {
            let parts = [String(characters[..<cut]), String(characters[cut...])]
            #expect(try collect(parts) == whole, "split at \(cut)")
        }
    }

    @Test("Feeding one character at a time yields the same events")
    func test_characterByCharacter() throws {
        let whole = try collect([document])
        #expect(try collect(document.map(String.init)) == whole)
    }

    @Test("Every token kind survives a mid-token split")
    func test_midTokenSplits() throws {
        let cases = [
            "<a b=\"v\"/>",
            "<!-- comment -->",
            "<![CDATA[data]]>",
            "<?target value?>",
            "<x>a &lt; b</x>",
        ]
        for fragment in cases {
            let whole = try collect([fragment])
            let mid = fragment.index(fragment.startIndex, offsetBy: fragment.count / 2)
            let parts = [String(fragment[..<mid]), String(fragment[mid...])]
            #expect(try collect(parts) == whole, "\(fragment)")
        }
    }

    @available(macOS 10.15, iOS 13, tvOS 13, watchOS 6, *)
    @Test("The async variant streams events from a chunk sequence")
    func test_async() async throws {
        let chunks = ["<doc>", "<item>a</item>", "<item>b</item>", "</doc>"]
        let stream = AsyncStream<String> { continuation in
            for chunk in chunks {
                continuation.yield(chunk)
            }
            continuation.finish()
        }
        var names: [String] = []
        for try await event in PureXML.events(feeding: stream) {
            if case let .startElement(name, _) = event { names.append(name.description) }
        }
        #expect(names == ["doc", "item", "item"])
    }
}
