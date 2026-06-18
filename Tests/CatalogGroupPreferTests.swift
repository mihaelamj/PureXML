import Testing
@testable import PureXML

@Suite("XML catalog group-level prefer override")
struct CatalogGroupPreferTests {
    private func resolver(_ xml: String) throws -> PureXML.Catalog.Resolver {
        try PureXML.Catalog.Resolver(xml)
    }

    @Test("A group prefer=system overrides a catalog prefer=public for its entries")
    func test_groupOverridesCatalog() throws {
        let xml = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="public">
          <public publicId="-//ROOT//EN" uri="root.dtd"/>
          <group prefer="system">
            <public publicId="-//GROUP//EN" uri="group.dtd"/>
          </group>
        </catalog>
        """
        let catalog = try resolver(xml)
        // Root entry inherits prefer=public: consulted even with an unmatched system id.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//ROOT//EN", systemID: "urn:unmatched") == "root.dtd")
        // Group entry is prefer=system: not consulted when a system id is present.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//GROUP//EN", systemID: "urn:unmatched") == nil)
        // But still consulted when there is no system id at all.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//GROUP//EN", systemID: nil) == "group.dtd")
    }

    @Test("A group prefer=public overrides a catalog prefer=system for its entries")
    func test_groupOverridesSystemCatalog() throws {
        let xml = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="system">
          <public publicId="-//ROOT//EN" uri="root.dtd"/>
          <group prefer="public">
            <public publicId="-//GROUP//EN" uri="group.dtd"/>
          </group>
        </catalog>
        """
        let catalog = try resolver(xml)
        // Root inherits prefer=system: public not consulted alongside a system id.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//ROOT//EN", systemID: "urn:unmatched") == nil)
        // Group entry is prefer=public: consulted even with an unmatched system id.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//GROUP//EN", systemID: "urn:unmatched") == "group.dtd")
    }

    @Test("A nested group inherits the enclosing group's prefer")
    func test_nestedGroupInherits() throws {
        let xml = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="public">
          <group prefer="system">
            <group>
              <public publicId="-//DEEP//EN" uri="deep.dtd"/>
            </group>
          </group>
        </catalog>
        """
        let catalog = try resolver(xml)
        // Deep entry inherits prefer=system through the inner group.
        #expect(catalog.resolveExternalIdentifier(publicID: "-//DEEP//EN", systemID: "urn:unmatched") == nil)
        #expect(catalog.resolveExternalIdentifier(publicID: "-//DEEP//EN", systemID: nil) == "deep.dtd")
    }

    @Test("A system match always wins regardless of group prefer")
    func test_systemAlwaysWins() throws {
        let xml = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog" prefer="public">
          <group prefer="system">
            <public publicId="-//P//EN" uri="by-public.dtd"/>
            <system systemId="urn:s" uri="by-system.dtd"/>
          </group>
        </catalog>
        """
        let catalog = try resolver(xml)
        #expect(catalog.resolveExternalIdentifier(publicID: "-//P//EN", systemID: "urn:s") == "by-system.dtd")
    }
}
