@testable import PureXML
import Testing

@Suite("XML Catalog")
struct CatalogTests {
    private let catalog = """
    <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
      <public publicId="-//W3C//DTD XHTML 1.0//EN" uri="local/xhtml1.dtd"/>
      <system systemId="http://example.com/note.dtd" uri="local/note.dtd"/>
      <rewriteSystem systemIdStartString="http://example.com/dtd/" rewritePrefix="local/dtd/"/>
      <uri name="urn:logo" uri="local/logo.png"/>
      <group>
        <rewriteURI uriStartString="http://example.com/img/" rewritePrefix="local/img/"/>
      </group>
    </catalog>
    """

    private func resolver() throws -> PureXML.Catalog.Resolver {
        try PureXML.Catalog.Resolver(catalog)
    }

    @Test("System and public identifiers resolve to their URIs")
    func test_exactEntries() throws {
        let resolver = try resolver()
        #expect(resolver.resolveSystem("http://example.com/note.dtd") == "local/note.dtd")
        #expect(resolver.resolvePublic("-//W3C//DTD XHTML 1.0//EN") == "local/xhtml1.dtd")
        #expect(resolver.resolveURI("urn:logo") == "local/logo.png")
    }

    @Test("rewriteSystem applies the longest matching prefix")
    func test_rewriteSystem() throws {
        let resolver = try resolver()
        #expect(resolver.resolveSystem("http://example.com/dtd/foo.dtd") == "local/dtd/foo.dtd")
    }

    @Test("rewriteURI inside a group is honored")
    func test_rewriteURIInGroup() throws {
        #expect(try resolver().resolveURI("http://example.com/img/a.png") == "local/img/a.png")
    }

    @Test("An unmapped identifier resolves to nil")
    func test_unmapped() throws {
        #expect(try resolver().resolveSystem("http://other/x.dtd") == nil)
    }

    @Test("The system identifier takes precedence over the public one")
    func test_systemPrecedence() throws {
        let resolver = try resolver()
        let uri = resolver.resolveExternalIdentifier(
            publicID: "-//W3C//DTD XHTML 1.0//EN",
            systemID: "http://example.com/note.dtd",
        )
        #expect(uri == "local/note.dtd")
    }

    @Test("The catalog drives an entity resolver through an injected loader")
    func test_entityResolverIntegration() throws {
        let resolver = try resolver().entityResolver { uri in
            uri == "local/note.dtd" ? "<!ENTITY greeting \"hi\">" : nil
        }
        let xml = "<!DOCTYPE r SYSTEM \"http://example.com/note.dtd\"><r>&greeting;</r>"
        let node = try PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver)
        #expect(stringValue(node) == "hi")
    }

    @Test("Without a loader the catalog resolver loads nothing, keeping XXE closed")
    func test_noLoaderRefuses() throws {
        let resolver = try resolver().entityResolver { _ in nil }
        let xml = "<!DOCTYPE r SYSTEM \"http://example.com/note.dtd\"><r>&greeting;</r>"
        #expect(throws: PureXML.Parsing.ParseError.self) {
            _ = try PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver)
        }
    }

    private func stringValue(_ node: PureXML.Model.Node) -> String {
        switch node {
        case let .document(children): children.map(stringValue).joined()
        case let .element(element): element.children.map(stringValue).joined()
        case let .text(value), let .cdata(value): value
        default: ""
        }
    }
}
