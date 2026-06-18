import Testing
@testable import PureXML

@Suite("RELAX NG streaming validation")
struct RelaxNGStreamingTests {
    private let grammar = """
    start = element library { book+ }
    book = element book { attribute id { text }, element title { text }, author+ }
    author = element author { text }
    """

    private let mixedGrammar = "start = element note { mixed { element b { text }* } }"

    /// Asserts streaming validation agrees with the tree engine, and matches the
    /// expected verdict. Streaming agreeing with the trusted tree walk on every
    /// document is the correctness proof for the derivative stepper.
    private func check(_ rnc: String, _ xml: String, expected: Bool) throws {
        let schema = try PureXML.Schema.RelaxNG(compact: rnc)
        let tree = try schema.validate(xml)
        let streamed = try schema.validate(streaming: xml)
        #expect(tree == streamed, "streaming disagreed with tree on: \(xml)")
        #expect(streamed == expected, "wrong verdict for: \(xml)")
    }

    @Test("Valid documents stream as valid and agree with the tree engine")
    func test_valid() throws {
        try check(grammar, "<library><book id=\"1\"><title>T</title><author>A</author></book></library>", expected: true)
        // Multiple books and authors (oneOrMore).
        try check(
            grammar,
            "<library><book id=\"1\"><title>T</title><author>A</author><author>B</author></book>"
                + "<book id=\"2\"><title>U</title><author>C</author></book></library>",
            expected: true,
        )
        // Ignorable whitespace between elements is allowed.
        try check(grammar, "<library>\n  <book id=\"1\"><title>T</title>\n    <author>A</author>\n  </book>\n</library>", expected: true)
    }

    @Test("Invalid documents stream as invalid and agree with the tree engine")
    func test_invalid() throws {
        // Missing required title.
        try check(grammar, "<library><book id=\"1\"><author>A</author></book></library>", expected: false)
        // Missing required attribute.
        try check(grammar, "<library><book><title>T</title><author>A</author></book></library>", expected: false)
        // Wrong order (group is ordered: title then author).
        try check(grammar, "<library><book id=\"1\"><author>A</author><title>T</title></book></library>", expected: false)
        // Empty library (book+ requires at least one).
        try check(grammar, "<library></library>", expected: false)
        // A stray element.
        try check(grammar, "<library><book id=\"1\"><title>T</title><author>A</author><stray/></book></library>", expected: false)
        // Character data where only elements are allowed.
        try check(grammar, "<library>text<book id=\"1\"><title>T</title><author>A</author></book></library>", expected: false)
    }

    @Test("Mixed content streams correctly (text interleaved with elements)")
    func test_mixed() throws {
        try check(mixedGrammar, "<note>hello <b>world</b> there</note>", expected: true)
        try check(mixedGrammar, "<note>just text</note>", expected: true)
        try check(mixedGrammar, "<note><b>x</b><b>y</b></note>", expected: true)
        // A disallowed child element fails even in mixed content.
        try check(mixedGrammar, "<note>text <i>no</i></note>", expected: false)
    }

    @Test("Streaming errors fall back to located tree diagnostics when invalid")
    func test_streamingErrors() throws {
        let schema = try PureXML.Schema.RelaxNG(compact: grammar)
        let bad = "<library><book id=\"1\"><author>A</author></book></library>"
        #expect(try schema.validate(streaming: bad) == false)
        let errors = try schema.errors(streaming: bad)
        #expect(!errors.isEmpty)
        #expect(try schema.errors(streaming: "<library><book id=\"1\"><title>T</title><author>A</author></book></library>").isEmpty)
    }
}
