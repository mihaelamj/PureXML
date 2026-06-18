import Testing
@testable import PureXML

@Suite("XSLT xsl:output cdata-section-elements")
struct XSLTCDATASectionTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func style(_ cdataElements: String, _ body: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes" cdata-section-elements="\(cdataElements)"/>
          <xsl:template match="/">\(body)</xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("A named element's text is emitted as a CDATA section")
    func test_wrapped() throws {
        let out = try transform(style("script", "<script>if (a &lt; b) go()</script>"), "<x/>")
        #expect(out == "<script><![CDATA[if (a < b) go()]]></script>")
    }

    @Test("An element not named keeps escaped text")
    func test_notNamed() throws {
        let out = try transform(style("script", "<data>a &lt; b</data>"), "<x/>")
        #expect(out == "<data>a &lt; b</data>")
    }

    @Test("Only the named element's own text is wrapped, not nested elements")
    func test_nestedUnaffected() throws {
        let out = try transform(style("outer", "<outer>x<inner>y &lt; z</inner></outer>"), "<x/>")
        #expect(out == "<outer><![CDATA[x]]><inner>y &lt; z</inner></outer>")
    }

    @Test("Multiple element names can be listed")
    func test_multiple() throws {
        let out = try transform(style("a b", "<root><a>1 &amp; 2</a><b>3 &amp; 4</b></root>"), "<x/>")
        #expect(out == "<root><a><![CDATA[1 & 2]]></a><b><![CDATA[3 & 4]]></b></root>")
    }
}
