@testable import PureXML
import Testing

@Suite("XSLT xsl:fallback")
struct XSLTFallbackTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func wrap(_ templateBody: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><out>\(templateBody)</out></xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("An unknown XSLT element instantiates its xsl:fallback")
    func test_unknownWithFallback() throws {
        let style = wrap("<xsl:future-thing><xsl:fallback>fb</xsl:fallback></xsl:future-thing>")
        #expect(try transform(style, "<x/>") == "<out>fb</out>")
    }

    @Test("An unknown XSLT element with no fallback is dropped")
    func test_unknownNoFallback() throws {
        let style = wrap("<xsl:future-thing/>kept")
        #expect(try transform(style, "<x/>") == "<out>kept</out>")
    }

    @Test("xsl:fallback under a supported instruction is ignored")
    func test_fallbackUnderSupported() throws {
        let style = wrap("<xsl:fallback>ignored</xsl:fallback>kept")
        #expect(try transform(style, "<x/>") == "<out>kept</out>")
    }

    @Test("Fallback content may itself be an instruction sequence")
    func test_fallbackSequence() throws {
        let style = wrap("<xsl:future-thing><xsl:fallback><a/><xsl:value-of select=\"r/@v\"/></xsl:fallback></xsl:future-thing>")
        #expect(try transform(style, "<r v=\"7\"/>") == "<out><a/>7</out>")
    }
}
