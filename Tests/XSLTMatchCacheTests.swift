import Testing
@testable import PureXML

@Suite("XSLT match-pattern caching")
struct XSLTMatchCacheTests {
    /// Guards the shape #112 optimized: many nodes against several templates,
    /// where each match pattern must be compiled and evaluated once per
    /// transform (not once per node) and selection must stay correct.
    @Test("A multi-template transform over hundreds of nodes selects correctly")
    func test_multiTemplateShape() throws {
        let rows = (1 ... 300).map { index in
            index.isMultiple(of: 2) ? "<even>\(index)</even>" : "<odd>\(index)</odd>"
        }.joined()
        let source = "<r>\(rows)</r>"
        let stylesheet = """
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:apply-templates select="/r/*"/></xsl:template>
          <xsl:template match="even">E</xsl:template>
          <xsl:template match="odd | never">O</xsl:template>
        </xsl:stylesheet>
        """
        let output = try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
        #expect(output.count == 300)
        #expect(output.count(where: { $0 == "E" }) == 150)
        #expect(output.count(where: { $0 == "O" }) == 150)
        // Alternation is preserved (selection by pattern, not by order accident).
        #expect(output.hasPrefix("OEOE"))
    }
}
