import Testing
@testable import PureXML

@Suite("XSLT key() with the context node and node-set values")
struct XSLTKeyNodeSetTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private let source = """
    <root>
      <item cat="a">1</item><item cat="a">2</item><item cat="b">3</item>
      <lookup>a</lookup><lookup>b</lookup>
    </root>
    """

    @Test("key('k', .) uses the context node's string value")
    func test_contextNode() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:key name="byCat" match="item" use="@cat"/>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:for-each select="//lookup"><xsl:value-of select="count(key('byCat', .))"/><xsl:text>,</xsl:text></xsl:for-each></xsl:template>
        </xsl:stylesheet>
        """
        // <lookup>a</lookup> -> 2 items, <lookup>b</lookup> -> 1 item.
        #expect(try transform(style, source) == "2,1,")
    }

    @Test("key('k', node-set) unions the matches for every node's value")
    func test_nodeSetValue() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:key name="byCat" match="item" use="@cat"/>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="count(key('byCat', //lookup))"/></xsl:template>
        </xsl:stylesheet>
        """
        // a -> 2, b -> 1, unioned and de-duplicated -> 3.
        #expect(try transform(style, source) == "3")
    }

    @Test("key with a string value still works")
    func test_stringValue() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:key name="byCat" match="item" use="@cat"/>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="count(key('byCat', 'a'))"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, source) == "2")
    }

    @Test("xsl:key with a union match pattern indexes every branch")
    func test_unionMatchPattern() throws {
        // match="a | b" indexes both a and b anywhere; the // must distribute over
        // the union (previously only the first branch was matched anywhere, so a
        // nested b was missed). Apache Xalan idkey45-48.
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:key name="k" match="a | b" use="@id"/>
          <xsl:template match="/"><out><xsl:for-each select="key('k','x')"><xsl:value-of select="name()"/>,</xsl:for-each></out></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<doc><a id=\"x\"/><wrap><b id=\"x\"/></wrap></doc>"
        #expect(try transform(style, source) == "<out>a,b,</out>")
    }
}
