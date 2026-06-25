import Testing
@testable import PureXML

/// `EntityExpander.expand` copies the literal text between references in bulk
/// rather than one character at a time. These pin that the bulk path produces
/// exactly the per-character result it replaced: references at the start, end,
/// and adjacent; literal runs of every length around them; decimal and hex
/// character references; declared-entity replacement (the budget-counted path,
/// including a bulk run that overflows the amplification budget); and a CDATA
/// section in replacement text copied verbatim without reference recognition.
@Suite("Entity decode bulk-copy equivalence")
struct EntityDecodeBulkTests {
    private typealias Decoder = PureXML.Parsing.EntityDecoder
    private static let mark = PureXML.Parsing.Mark(line: 1, column: 1, offset: 0)

    private func decode(_ raw: String, entities: [String: String] = [:], budget: Int = 1_000_000) throws -> String {
        var remaining = budget
        return try Decoder.decode(raw, entities: entities, budget: &remaining, at: Self.mark)
    }

    @Test("predefined references inside literal runs decode in place")
    func test_predefinedRuns() throws {
        #expect(try decode("plain text with no references") == "plain text with no references")
        #expect(try decode("a&amp;b") == "a&b")
        #expect(try decode("x &amp; y &lt; z &gt; w &quot;q&quot; &apos;a&apos;") == "x & y < z > w \"q\" 'a'")
        #expect(try decode("&amp;&lt;&gt;") == "&<>")
        #expect(try decode("&amp;tail") == "&tail")
        #expect(try decode("head&amp;") == "head&")
        // A long literal run on each side of a single reference (the bulk case).
        let long = String(repeating: "abcde ", count: 200)
        #expect(try decode("\(long)&amp;\(long)") == "\(long)&\(long)")
    }

    @Test("character references decode decimal and hex")
    func test_characterReferences() throws {
        #expect(try decode("&#65;&#x42;C") == "ABC")
        #expect(try decode("pre &#x263A; post") == "pre \u{263A} post")
    }

    @Test("declared entity replacement expands and counts against the budget")
    func test_declaredReplacement() throws {
        #expect(try decode("<&e;>", entities: ["e": "REPLACEMENT"]) == "<REPLACEMENT>")
        // A replacement run longer than the remaining budget overflows: the
        // per-character path threw at the overrunning character, the bulk path
        // throws on the whole run; both reject the decode.
        #expect(throws: (any Error).self) {
            try decode("&e;", entities: ["e": "ABCDE"], budget: 3)
        }
        // Exactly the budget is allowed (the boundary the per-character guard
        // permitted).
        #expect(try decode("&e;", entities: ["e": "ABCDE"], budget: 5) == "ABCDE")
    }

    @Test("a CDATA section in replacement text is copied verbatim")
    func test_cdataInReplacement() throws {
        // The '&not;' inside CDATA must not be treated as a reference.
        #expect(try decode("&e;", entities: ["e": "<![CDATA[a&not;b]]>"]) == "<![CDATA[a&not;b]]>")
    }

    @Test("an unterminated reference is rejected")
    func test_unterminatedReference() throws {
        #expect(throws: (any Error).self) {
            try decode("text &amp without a semicolon")
        }
    }

    @Test("text with references decodes through the parser to one text node")
    func test_throughParser() throws {
        let node = try PureXML.parse("<r>x &amp; y &lt; z &gt; w</r>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root")
            return
        }
        let text = root.children.compactMap { if case let .text(value) = $0 { value } else { nil } }.joined()
        #expect(text == "x & y < z > w")
    }
}
