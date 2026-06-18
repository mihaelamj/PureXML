import Testing
@testable import PureXML

@Suite("Catalog suffix entries and prefer attribute")
struct CatalogSuffixPreferTests {
    @Test("systemSuffix resolves by longest matching suffix")
    func test_systemSuffix() throws {
        let catalog = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <systemSuffix systemIdSuffix=".dtd" uri="generic.dtd"/>
          <systemSuffix systemIdSuffix="docbook.dtd" uri="docbook.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveSystem("http://x/foo.dtd") == "generic.dtd")
        // The longer matching suffix wins.
        #expect(resolver.resolveSystem("http://x/docbook.dtd") == "docbook.dtd")
        #expect(resolver.resolveSystem("http://x/foo.xsd") == nil)
    }

    @Test("uriSuffix resolves a URI name by suffix")
    func test_uriSuffix() throws {
        let catalog = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <uriSuffix uriSuffix=".xsd" uri="schema.xsd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveURI("http://x/types.xsd") == "schema.xsd")
        #expect(resolver.resolveURI("http://x/types.dtd") == nil)
    }

    @Test("An exact system entry still wins over a suffix")
    func test_exactBeatsSuffix() throws {
        let catalog = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <system systemId="http://x/foo.dtd" uri="exact.dtd"/>
          <systemSuffix systemIdSuffix=".dtd" uri="generic.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        #expect(resolver.resolveSystem("http://x/foo.dtd") == "exact.dtd")
    }

    @Test("prefer=public falls back to a public entry when the system id is unmatched")
    func test_preferPublic() throws {
        let catalog = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="public">
          <public publicId="-//X//DTD//EN" uri="bypublic.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        let resolved = resolver.resolveExternalIdentifier(publicID: "-//X//DTD//EN", systemID: "http://x/unmatched.dtd")
        #expect(resolved == "bypublic.dtd")
    }

    @Test("prefer=system does not fall back to public when a system id is present")
    func test_preferSystem() throws {
        let catalog = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="system">
          <public publicId="-//X//DTD//EN" uri="bypublic.dtd"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(catalog)
        // A system id is present but unmatched, and prefer=system, so no fallback.
        #expect(resolver.resolveExternalIdentifier(publicID: "-//X//DTD//EN", systemID: "http://x/unmatched.dtd") == nil)
        // With no system id, the public entry is still used.
        #expect(resolver.resolveExternalIdentifier(publicID: "-//X//DTD//EN", systemID: nil) == "bypublic.dtd")
    }
}
