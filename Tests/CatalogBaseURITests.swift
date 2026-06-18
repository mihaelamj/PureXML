import Testing
@testable import PureXML

@Suite("Catalog xml:base and RFC 3986 URI resolution")
struct CatalogBaseURITests {
    private let nsAttr = "xmlns=\"urn:oasis:names:tc:entity:xmlns:xml:catalog\""

    @Test("A relative entry URI resolves against the catalog base URI")
    func test_baseURI() throws {
        let catalog = """
        <catalog \(nsAttr)>
          <system systemId="urn:x" uri="dtd/x.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog, baseURI: "http://example.org/cat/catalog.xml")
        #expect(resolver.resolveSystem("urn:x") == "http://example.org/cat/dtd/x.dtd")
    }

    @Test("xml:base on the catalog element scopes its entries")
    func test_xmlBaseOnCatalog() throws {
        let catalog = """
        <catalog \(nsAttr) xml:base="http://example.org/base/">
          <uri name="urn:u" uri="schema.xsd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveURI("urn:u") == "http://example.org/base/schema.xsd")
    }

    @Test("A nested xml:base resolves relative to the outer base")
    func test_nestedXmlBase() throws {
        let catalog = """
        <catalog \(nsAttr) xml:base="http://example.org/a/">
          <group xml:base="b/">
            <system systemId="urn:s" uri="x.dtd"/>
          </group>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveSystem("urn:s") == "http://example.org/a/b/x.dtd")
    }

    @Test("rewritePrefix and an absolute URI are resolved or left absolute")
    func test_rewriteAndAbsolute() throws {
        let catalog = """
        <catalog \(nsAttr)>
          <rewriteSystem systemIdStartString="urn:p:" rewritePrefix="local/"/>
          <system systemId="urn:abs" uri="http://other.org/y.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog, baseURI: "http://example.org/c/catalog.xml")
        #expect(resolver.resolveSystem("urn:p:thing") == "http://example.org/c/local/thing")
        // An absolute entry URI stays absolute regardless of the base.
        #expect(resolver.resolveSystem("urn:abs") == "http://other.org/y.dtd")
    }

    @Test("With no base, relative URIs are left unchanged (backward compatible)")
    func test_noBaseUnchanged() throws {
        let catalog = """
        <catalog \(nsAttr)>
          <system systemId="urn:x" uri="x.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveSystem("urn:x") == "x.dtd")
    }
}
