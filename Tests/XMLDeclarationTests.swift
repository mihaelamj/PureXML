import Testing
@testable import PureXML

@Suite("XML declaration")
struct XMLDeclarationTests {
    @Test("version, encoding, and standalone are all surfaced")
    func test_full() {
        let declaration = PureXML.xmlDeclaration("<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?><r/>")
        #expect(declaration?.version == "1.0")
        #expect(declaration?.encoding == "UTF-8")
        #expect(declaration?.standalone == true)
    }

    @Test("standalone=no is parsed as false")
    func test_standaloneNo() {
        let declaration = PureXML.xmlDeclaration("<?xml version=\"1.1\" standalone=\"no\"?><r/>")
        #expect(declaration?.version == "1.1")
        #expect(declaration?.standalone == false)
    }

    @Test("A version-only declaration leaves encoding and standalone nil")
    func test_versionOnly() {
        let declaration = PureXML.xmlDeclaration("<?xml version=\"1.0\"?><r/>")
        #expect(declaration?.version == "1.0")
        #expect(declaration?.encoding == nil)
        #expect(declaration?.standalone == nil)
    }

    @Test("A document without a declaration has none")
    func test_none() {
        #expect(PureXML.xmlDeclaration("<r/>") == nil)
    }

    @Test("Pseudo-attributes out of order are rejected")
    func test_outOfOrder() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<?xml encoding=\"UTF-8\" version=\"1.0\"?><r/>")
        }
    }

    @Test("An illegal standalone value is rejected")
    func test_badStandalone() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<?xml version=\"1.0\" standalone=\"maybe\"?><r/>")
        }
    }

    @Test("An unknown pseudo-attribute is rejected")
    func test_unknownPseudoAttribute() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse("<?xml version=\"1.0\" mode=\"strict\"?><r/>")
        }
    }

    @Test("A valid declaration still parses the document tree")
    func test_treeStillParses() throws {
        let node = try PureXML.parse("<?xml version=\"1.0\"?><r>hi</r>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root")
            return
        }
        #expect(root.name.localName == "r")
    }
}
