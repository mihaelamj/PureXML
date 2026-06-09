@testable import PureXML
import Testing

@Suite("XSLT method=html output")
struct XSLTHTMLOutputTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func htmlStyle(_ body: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="html"/>
          <xsl:template match="/">\(body)</xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("A void element is emitted without a self-closing slash")
    func test_voidElement() throws {
        let out = try transform(htmlStyle("<br/>"), "<x/>")
        #expect(out == "<br>")
    }

    @Test("A non-void empty element keeps an explicit end tag")
    func test_nonVoid() throws {
        let out = try transform(htmlStyle("<div/>"), "<x/>")
        #expect(out == "<div></div>")
    }

    @Test("Raw-text element content is not escaped")
    func test_rawText() throws {
        let out = try transform(htmlStyle("<script>if (a &lt; b) x()</script>"), "<x/>")
        #expect(out.contains("if (a < b) x()"))
        #expect(!out.contains("&lt;"))
    }

    @Test("The XML output method still self-closes empty elements")
    func test_xmlStillSelfCloses() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><br/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<br/>")
    }
}
