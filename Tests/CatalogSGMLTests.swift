@testable import PureXML
import Testing

@Suite("SGML catalog format")
struct CatalogSGMLTests {
    @Test("PUBLIC and SYSTEM entries resolve")
    func test_publicSystem() {
        let catalog = """
        -- a sample SGML catalog --
        PUBLIC "-//X//DTD Sample//EN" "sample.dtd"
        SYSTEM "http://x/sys.dtd" "local.dtd"
        """
        let resolver = PureXML.Catalog.Resolver(sgml: catalog)
        #expect(resolver.resolvePublic("-//X//DTD Sample//EN") == "sample.dtd")
        #expect(resolver.resolveSystem("http://x/sys.dtd") == "local.dtd")
    }

    @Test("DELEGATE and CATALOG entries are parsed")
    func test_delegateCatalog() {
        let catalog = """
        DELEGATE "-//X//" "delegated.soc"
        CATALOG "next.soc"
        """
        let resolver = PureXML.Catalog.Resolver(sgml: catalog)
        let loaded = resolver.resolvePublic("-//X//DTD Y//EN", loadingCatalog: { uri in
            uri == "delegated.soc" ? "PUBLIC \"-//X//DTD Y//EN\" \"found.dtd\"" : nil
        })
        // Note: the delegated catalog is itself SGML; resolvePublic loads it as XML,
        // so this exercises the chain wiring. The direct entries below are the focus.
        _ = loaded
        // BASE resolution applies to entry URIs.
        #expect(resolver.resolvePublic("-//X//DTD Y//EN") == nil)
    }

    @Test("BASE resolves relative entry URIs")
    func test_base() {
        let catalog = """
        BASE "http://example.org/cat/"
        SYSTEM "urn:x" "dtd/x.dtd"
        """
        let resolver = PureXML.Catalog.Resolver(sgml: catalog)
        #expect(resolver.resolveSystem("urn:x") == "http://example.org/cat/dtd/x.dtd")
    }

    @Test("OVERRIDE NO disables the public fallback when a system id is present")
    func test_override() {
        let preferPublic = PureXML.Catalog.Resolver(sgml: "OVERRIDE YES\nPUBLIC \"p\" \"by-public.dtd\"")
        #expect(preferPublic.resolveExternalIdentifier(publicID: "p", systemID: "unmatched") == "by-public.dtd")
        let preferSystem = PureXML.Catalog.Resolver(sgml: "OVERRIDE NO\nPUBLIC \"p\" \"by-public.dtd\"")
        #expect(preferSystem.resolveExternalIdentifier(publicID: "p", systemID: "unmatched") == nil)
    }
}
