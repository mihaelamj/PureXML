@testable import PureXML
import Testing

/// Scalar-level lexing (#135): a combining mark directly after an ASCII
/// delimiter must not merge with it into one grapheme cluster, so Fifth
/// Edition name characters lex correctly, while grapheme clusters still
/// reassemble in scanned text content.
@Suite("Scalar-level lexing")
struct ScalarLexingTests {
    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    @Test("A combining-mark name character after a delimiter lexes correctly")
    func test_combiningMarkNames() throws {
        // U+06D6 clusters with the preceding '?' as a Swift grapheme; per 5e
        // it is a NameStartChar and a legal PI target.
        let instruction = "<!DOCTYPE doc [<!ELEMENT doc ANY><?\u{06D6} data ?>]>\n<doc/>"
        #expect((try? PureXML.parse(instruction, limits: limits())) != nil)
        // U+309A as an element name via declaration-expanded markup.
        let element = "<!DOCTYPE doc [<!ENTITY e \"<\u{309A}></\u{309A}>\">]>\n<doc>&e;</doc>"
        let node = try PureXML.parse(element, limits: limits())
        guard case let .document(children) = node, let doc = children.compactMap(\.element).first else {
            Issue.record("no root")
            return
        }
        #expect(doc.children.compactMap(\.element).first?.name.localName == "\u{309A}")
    }

    @Test("ZWNJ and ZWJ are name characters in attribute names")
    func test_zeroWidthJoiners() throws {
        let xml = "<doc \u{200C}\u{200D}attr=\"v\"/>"
        let node = try PureXML.parse(xml)
        guard case let .document(children) = node, case let .element(doc)? = children.first else {
            Issue.record("no root")
            return
        }
        #expect(doc.attributes.first?.name.localName == "\u{200C}\u{200D}attr")
    }

    @Test("Grapheme clusters reassemble in text content")
    func test_textReassembly() throws {
        // e + combining acute arrive as separate scalars and recombine.
        let xml = "<doc>e\u{0301}x</doc>"
        let node = try PureXML.parse(xml)
        guard case let .document(children) = node, case let .element(doc)? = children.first,
              case let .text(value)? = doc.children.first
        else {
            Issue.record("no text")
            return
        }
        #expect(value == "e\u{0301}x")
        #expect(Array(value).count == 2)
    }
}
