import Testing
@testable import PureXML

/// Content splicing (4.4.2 Included, #133): a general entity whose replacement
/// text contains markup is reparsed as content, so elements inside an entity
/// become elements in the tree and in the pull-event stream, with character
/// references expanded at declaration time (4.4.5).
@Suite("Entity replacement splicing")
struct EntitySplicingTests {
    private func limits() -> PureXML.Parsing.Limits {
        PureXML.Parsing.Limits(allowDoctype: true)
    }

    private let document = """
    <!DOCTYPE root [
    <!ELEMENT root (p)>
    <!ELEMENT p (#PCDATA)>
    <!ENTITY example "<p>text</p>">
    ]>
    <root>&example;</root>
    """

    @Test("An entity's markup becomes elements in the tree")
    func test_treeShape() throws {
        let node = try PureXML.parse(document, limits: limits())
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root")
            return
        }
        #expect(root.children.count == 1)
        guard case let .element(paragraph)? = root.children.first else {
            Issue.record("expected a p element, got \(String(describing: root.children.first))")
            return
        }
        #expect(paragraph.name.localName == "p")
        #expect(paragraph.children.count == 1)
        if case let .text(value)? = paragraph.children.first {
            #expect(value == "text")
        } else {
            Issue.record("expected text inside p")
        }
    }

    @Test("The pull-event stream sees the spliced elements")
    func test_pullEvents() throws {
        var reader = PureXML.Parsing.EventReader(document, limits: limits())
        var names: [String] = []
        while let event = try reader.next() {
            switch event {
            case let .startElement(name, _): names.append("+\(name.localName)")
            case let .endElement(name): names.append("-\(name.localName)")
            case let .characters(text) where !text.isEmpty: names.append("t:\(text)")
            default: break
            }
        }
        #expect(names == ["+root", "+p", "t:text", "-p", "-root"])
    }

    @Test("The spliced document validates against its DTD content model")
    func test_dtdValidates() throws {
        let errors = try PureXML.validateAgainstInternalDTD(document, limits: limits())
        #expect(errors.isEmpty, "\(errors)")
    }

    @Test("Character references expand at declaration, so markup from them splices")
    func test_characterReferenceMarkup() throws {
        // xmltest valid/sa/024 and 087 shapes.
        let viaCharRef = """
        <!DOCTYPE doc [
        <!ELEMENT doc (foo)>
        <!ELEMENT foo (#PCDATA)>
        <!ENTITY e "&#60;foo></foo>">
        ]>
        <doc>&e;</doc>
        """
        let node = try PureXML.parse(viaCharRef, limits: limits())
        guard case let .document(children) = node, let doc = children.compactMap(\.element).first else {
            Issue.record("no root")
            return
        }
        #expect(doc.children.compactMap(\.element).first?.name.localName == "foo")
    }

    @Test("The Appendix D double escape yields a literal ampersand in content")
    func test_doubleEscape() throws {
        let xml = """
        <!DOCTYPE doc [
        <!ELEMENT doc (#PCDATA)>
        <!ENTITY e "a &#38;#38; b">
        ]>
        <doc>&e;</doc>
        """
        let node = try PureXML.parse(xml, limits: limits())
        guard case let .document(children) = node, let doc = children.compactMap(\.element).first,
              case let .text(value)? = doc.children.first
        else {
            Issue.record("no text")
            return
        }
        #expect(value == "a & b")
    }

    @Test("A recursive markup entity is rejected, not looped")
    func test_recursionRejected() {
        let xml = """
        <!DOCTYPE doc [
        <!ELEMENT doc ANY>
        <!ENTITY a "<p>&a;</p>">
        ]>
        <doc>&a;</doc>
        """
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: limits())
        }
    }

    @Test("Tags spanning the entity boundary stay rejected")
    func test_boundarySpanRejected() {
        let xml = """
        <!DOCTYPE doc [
        <!ELEMENT doc ANY>
        <!ENTITY e "</doc><doc>">
        ]>
        <doc>&e;</doc>
        """
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: limits())
        }
    }
}
