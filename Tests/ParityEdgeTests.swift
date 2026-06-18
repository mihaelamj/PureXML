import Testing
@testable import PureXML

@Suite("Parity edges: C14N 2.0, catalog delegation, XPath number formatting")
struct ParityEdgeTests {
    // MARK: XPath number formatting

    @Test("XPath formats numbers as plain decimals without an exponent")
    func test_numberFormatting() {
        #expect(PureXML.XPath.Value.format(0.000015) == "0.000015")
        #expect(PureXML.XPath.Value.format(1.23e21) == "1230000000000000000000")
        #expect(PureXML.XPath.Value.format(-0.5) == "-0.5")
        #expect(PureXML.XPath.Value.format(3) == "3")
        #expect(PureXML.XPath.Value.format(Double.nan) == "NaN")
    }

    @Test("A small fractional XPath result avoids scientific notation")
    func test_numberFromQuery() throws {
        let result = try PureXML.XPath.Query("1 div 100000").number(over: .text(""))
        #expect(PureXML.XPath.Value.format(result) == "0.00001")
    }

    // MARK: Catalog delegation and nextCatalog

    @Test("delegateSystem resolves through the delegated catalog")
    func test_delegateSystem() throws {
        let delegated = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <system systemId="http://example.com/a.dtd" uri="local/a.dtd"/>
        </catalog>
        """
        let main = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <delegateSystem systemIdStartString="http://example.com/" catalog="sub.xml"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(main)
        let loader: (String) -> String? = { $0 == "sub.xml" ? delegated : nil }
        #expect(resolver.resolveSystem("http://example.com/a.dtd", loadingCatalog: loader) == "local/a.dtd")
        #expect(resolver.resolveSystem("http://other.com/a.dtd", loadingCatalog: loader) == nil)
    }

    @Test("nextCatalog chains to a following catalog")
    func test_nextCatalog() throws {
        let next = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <public publicId="-//Example//DTD//EN" uri="example.dtd"/>
        </catalog>
        """
        let main = """
        <catalog xmlns="urn:oasis:names:tc:entity:xmlns:xml:catalog">
          <nextCatalog catalog="next.xml"/>
        </catalog>
        """
        let resolver = try PureXML.Catalog.Resolver(main)
        let loader: (String) -> String? = { $0 == "next.xml" ? next : nil }
        #expect(resolver.resolvePublic("-//Example//DTD//EN", loadingCatalog: loader) == "example.dtd")
    }

    // MARK: Canonical XML 2.0 text trimming

    @Test("C14N 2.0 TrimTextNodes strips text-node whitespace")
    func test_canonical2Trim() throws {
        let node = try PureXML.parse("<r><a>  spaced  </a><b>\n  x\n  </b></r>")
        let trimmed = PureXML.Canonical.canonicalize(node, options: .canonical2)
        #expect(trimmed == "<r><a>spaced</a><b>x</b></r>")
        let untrimmed = PureXML.Canonical.canonicalize(node, options: .inclusive)
        #expect(untrimmed == "<r><a>  spaced  </a><b>\n  x\n  </b></r>")
    }
}
