import Testing
@testable import PureXML

@Suite("Namespaces")
struct NamespaceTests {
    @Test("Default namespace applies to the element and inherits to children")
    func test_defaultNamespace() throws {
        let root = try rootElement("<r xmlns=\"http://x\"><c/></r>")
        #expect(root.name.namespaceURI == "http://x")
        #expect(firstChildElement(root)?.name.namespaceURI == "http://x")
    }

    @Test("Prefixed element and attribute names resolve to their URI")
    func test_prefixedResolution() throws {
        let root = try rootElement("<a xmlns:p=\"http://p\" p:x=\"1\"><p:b/></a>")
        #expect(root.name.namespaceURI == nil)
        let prefixed = root.attributes.first { $0.name.localName == "x" }
        #expect(prefixed?.name.namespaceURI == "http://p")
        #expect(firstChildElement(root)?.name.namespaceURI == "http://p")
    }

    @Test("Default namespace does not apply to unprefixed attributes")
    func test_defaultNamespaceSkipsAttributes() throws {
        let root = try rootElement("<a xmlns=\"http://x\" id=\"1\"/>")
        #expect(root.name.namespaceURI == "http://x")
        let identifier = root.attributes.first { $0.name.localName == "id" }
        #expect(identifier?.name.namespaceURI == nil)
    }

    @Test("The xml prefix is bound to the reserved namespace")
    func test_xmlPrefixReserved() throws {
        let root = try rootElement("<a xml:lang=\"en\"/>")
        let lang = root.attributes.first { $0.name.localName == "lang" }
        #expect(lang?.name.namespaceURI == PureXML.Parsing.NamespaceContext.xmlNamespaceURI)
    }

    @Test("An unbound prefix is rejected")
    func test_unboundPrefixRejected() {
        #expect(throws: PureXML.Parsing.ParseError.self) {
            try PureXML.parse("<a><q:b/></a>")
        }
    }

    @Test("xmlns declarations are preserved as attributes for round-trip")
    func test_xmlnsDeclarationPreserved() throws {
        let root = try rootElement("<a xmlns:p=\"http://p\"/>")
        #expect(root.attributes.contains { $0.name.description == "xmlns:p" })
    }

    @Test("A redeclared default namespace is scoped and reverts")
    func test_scopedRedeclaration() throws {
        let root = try rootElement("<r xmlns=\"http://1\"><m xmlns=\"http://2\"/><n/></r>")
        #expect(root.name.namespaceURI == "http://1")
        let children = root.children.compactMap { node -> PureXML.Model.Element? in
            if case let .element(element) = node { return element }
            return nil
        }
        #expect(children.first?.name.namespaceURI == "http://2")
        #expect(children.last?.name.namespaceURI == "http://1")
    }

    private func rootElement(_ xml: String) throws -> PureXML.Model.Element {
        let node = try PureXML.parse(xml)
        guard case let .document(children) = node else {
            throw Failure.notDocument
        }
        for child in children {
            if case let .element(element) = child { return element }
        }
        throw Failure.noElement
    }

    private func firstChildElement(_ element: PureXML.Model.Element) -> PureXML.Model.Element? {
        for child in element.children {
            if case let .element(found) = child { return found }
        }
        return nil
    }

    private enum Failure: Error { case notDocument, noElement }
}
