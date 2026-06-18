import Testing
@testable import PureXML

@Suite("XSLT xsl:apply-imports")
struct XSLTApplyImportsTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String, loader: @escaping (String) -> String?) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source, documentLoader: loader)
    }

    @Test("apply-imports invokes the lower-precedence imported template")
    func test_applyImports() throws {
        let base = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="item">[base:<xsl:value-of select="."/>]</xsl:template>
        </xsl:stylesheet>
        """
        let main = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="base.xsl"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="r/item"/></out></xsl:template>
          <xsl:template match="item">main(<xsl:apply-imports/>)</xsl:template>
        </xsl:stylesheet>
        """
        let output = try transform(main, "<r><item>x</item></r>") { $0 == "base.xsl" ? base : nil }
        #expect(output == "<out>main([base:x])</out>")
    }

    @Test("apply-imports with no lower-precedence match falls back to the built-in rule")
    func test_applyImportsBuiltIn() throws {
        let base = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="other">never</xsl:template>
        </xsl:stylesheet>
        """
        let main = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="base.xsl"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="r/item"/></out></xsl:template>
          <xsl:template match="item">main[<xsl:apply-imports/>]</xsl:template>
        </xsl:stylesheet>
        """
        // No imported template matches "item", so apply-imports uses the built-in
        // rule, which outputs the element's text value.
        let output = try transform(main, "<r><item>y</item></r>") { $0 == "base.xsl" ? base : nil }
        #expect(output == "<out>main[y]</out>")
    }
}
