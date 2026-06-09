@testable import PureXML
import Testing

@Suite("XSLT result-tree fragment as node-set")
struct XSLTResultFragmentTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func body(_ select: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/">
            <xsl:variable name="rtf"><a>1</a><b>2</b><a>3</a></xsl:variable>
            <xsl:value-of select="\(select)"/>
          </xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("count($rtf/*) counts the fragment's top-level elements")
    func test_countAll() throws {
        #expect(try transform(body("count($rtf/*)"), "<x/>") == "3")
    }

    @Test("A name test selects matching fragment children")
    func test_nameTest() throws {
        #expect(try transform(body("count($rtf/a)"), "<x/>") == "2")
    }

    @Test("A path into the fragment reads a child's value")
    func test_childValue() throws {
        #expect(try transform(body("$rtf/b"), "<x/>") == "2")
    }

    @Test("The fragment still has a string value (its concatenated text)")
    func test_stringValue() throws {
        #expect(try transform(body("string($rtf)"), "<x/>") == "123")
    }

    @Test("for-each iterates the fragment's nodes")
    func test_forEach() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/">
            <xsl:variable name="rtf"><a>1</a><b>2</b><a>3</a></xsl:variable>
            <xsl:for-each select="$rtf/a"><xsl:value-of select="."/><xsl:text>,</xsl:text></xsl:for-each>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "1,3,")
    }
}
