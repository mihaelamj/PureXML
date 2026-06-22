import Testing
@testable import PureXML

/// Standing coverage for two value types the coverage gate (scripts/check-coverage.sh)
/// flagged at 0%: the HTML tokenizer's `Token` (a custom Equatable) and the public
/// `Stream.Document` (constructed by API consumers, never internally). Both are small
/// but their equality/accessors had no test exercising them.
@Suite("Value-type coverage (HTML Token, Stream.Document)")
struct CoverageGateValueTypeTests {
    private typealias Token = PureXML.HTML.Token

    @Test("HTML Token equality compares names, attributes, self-closing, and kind")
    func test_htmlTokenEquality() {
        #expect(Token.startTag(name: "a", attributes: [("href", "x")], selfClosing: false)
            == Token.startTag(name: "a", attributes: [("href", "x")], selfClosing: false))
        // A differing attribute value, attribute name, or self-closing flag is unequal.
        #expect(Token.startTag(name: "a", attributes: [("id", "1")], selfClosing: false)
            != Token.startTag(name: "a", attributes: [("id", "2")], selfClosing: false))
        #expect(Token.startTag(name: "a", attributes: [("id", "1")], selfClosing: false)
            != Token.startTag(name: "a", attributes: [("class", "1")], selfClosing: false))
        #expect(Token.startTag(name: "a", attributes: [], selfClosing: true)
            != Token.startTag(name: "a", attributes: [], selfClosing: false))
        #expect(Token.endTag(name: "p") == Token.endTag(name: "p"))
        #expect(Token.text("x") == Token.text("x"))
        #expect(Token.comment("c") == Token.comment("c"))
        #expect(Token.doctype("html") == Token.doctype("html"))
        // Different kinds with the same payload are unequal (the default branch).
        #expect(Token.text("x") != Token.comment("x"))
    }

    @Test("Stream.Document carries its index and node with value equality")
    func test_streamDocument() throws {
        let node = try PureXML.parse("<a/>")
        let doc = PureXML.Stream.Document(index: 2, node: node)
        #expect(doc.index == 2)
        #expect(doc.node == node)
        #expect(doc == PureXML.Stream.Document(index: 2, node: node))
        #expect(doc != PureXML.Stream.Document(index: 3, node: node))
    }
}
