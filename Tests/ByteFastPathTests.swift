import Testing
@testable import PureXML

/// Locks the parser's byte-level fast paths against their Character-path
/// fallbacks. Each case is chosen to land exactly on a boundary where the byte
/// scanner must hand off to the scalar scanner (a non-ASCII byte, a carriage
/// return, an entity reference) so that a future change to either path cannot
/// silently diverge. The expected values are the spec-correct results,
/// independent of which path produced them.
@Suite("Byte fast-path boundaries")
struct ByteFastPathTests {
    @Test("An all-ASCII name uses the byte path; a non-ASCII name falls back")
    func test_nameFallback() throws {
        let node = try PureXML.parse("<caf\u{e9} na\u{ef}ve=\"x\">y</caf\u{e9}>")
        let element = node.firstElement
        #expect(element?.name.localName == "caf\u{e9}")
        #expect(element?.attributes == [.init("na\u{ef}ve", "x")])
        #expect(element?.text == "y")
    }

    @Test("A name whose ASCII prefix precedes a non-ASCII byte stays whole")
    func test_mixedNameStaysWhole() throws {
        // The byte scanner consumes "ab", meets the non-ASCII byte, returns nil,
        // and the Character path re-scans the entire "ab\u{e9}" as one name.
        let node = try PureXML.parse("<ab\u{e9}/>")
        #expect(node.firstElement?.name.localName == "ab\u{e9}")
    }

    @Test("A prefixed name splits at the colon on the byte path")
    func test_prefixedName() throws {
        let node = try PureXML.parse("<m:row xmlns:m=\"urn:x\" m:k=\"v\"/>")
        let element = node.firstElement
        #expect(element?.name.prefix == "m")
        #expect(element?.name.localName == "row")
        #expect(element?.attributes.contains { $0.name.localName == "k" && $0.value == "v" } == true)
    }

    @Test("Literal whitespace in an attribute value normalizes to single spaces")
    func test_attributeWhitespaceNormalizes() throws {
        // Tab and line feed each become one space per 3.3.3; these run through
        // the byte scanner's whitespace transform.
        let node = try PureXML.parse("<a v=\"x\ty\nz\"/>")
        #expect(node.firstElement?.attributes == [.init("v", "x y z")])
    }

    @Test("A CRLF in an attribute value collapses to a single space")
    func test_attributeCRLF() throws {
        // 2.11 folds CRLF to one LF before 3.3.3 turns it into one space. The
        // byte scanner defers any carriage return to the Character path so the
        // pair is not double-counted as two spaces.
        let node = try PureXML.parse("<a v=\"x\r\ny\"/>")
        #expect(node.firstElement?.attributes == [.init("v", "x y")])
    }

    @Test("A character reference in an attribute value survives normalization")
    func test_attributeCharReferenceSurvives() throws {
        // A referenced line feed is NOT subject to whitespace normalization: it
        // stays a line feed while a literal line feed would have become a space.
        let node = try PureXML.parse("<a v=\"x&#10;y\"/>")
        #expect(node.firstElement?.attributes == [.init("v", "x\ny")])
    }

    @Test("Entities and bare ampersands in text decode through the slow path")
    func test_textEntities() throws {
        let node = try PureXML.parse("<p>plain text then 1 &lt; 2 &amp; ok</p>")
        #expect(node.firstElement?.text == "plain text then 1 < 2 & ok")
    }

    @Test("Ampersand-free text is returned verbatim")
    func test_textWithoutEntities() throws {
        let node = try PureXML.parse("<p>just plain ascii content, no references</p>")
        #expect(node.firstElement?.text == "just plain ascii content, no references")
    }

    @Test("A CRLF inside text content folds to a single line feed")
    func test_textCRLF() throws {
        let node = try PureXML.parse("<p>line one\r\nline two</p>")
        #expect(node.firstElement?.text == "line one\nline two")
    }

    @Test("Non-ASCII text content round-trips unchanged")
    func test_nonASCIIText() throws {
        let node = try PureXML.parse("<p>caf\u{e9} na\u{ef}ve r\u{e9}sum\u{e9}</p>")
        #expect(node.firstElement?.text == "caf\u{e9} na\u{ef}ve r\u{e9}sum\u{e9}")
    }

    @Test("An over-long ASCII name is rejected, not silently truncated")
    func test_longNameRejected() {
        let limits = PureXML.Parsing.Limits(maxNameLength: 4)
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<abcdefgh/>", limits: limits)
        }
    }

    @Test("A raw less-than inside an attribute value is rejected")
    func test_rawLessThanInAttribute() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a v=\"x<y\"/>")
        }
    }

    @Test("A leading greater-than in text content is preserved")
    func test_textLeadingGreaterThan() throws {
        let node = try PureXML.parse("<p>a > b</p>")
        #expect(node.firstElement?.text == "a > b")
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
