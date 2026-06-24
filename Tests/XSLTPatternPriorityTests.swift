import Testing
@testable import PureXML

/// XSLT 1.0 5.5 default-priority rules for template match patterns.
@Suite("XSLT pattern priority")
struct XSLTPatternPriorityTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("an axis-prefixed node test ties with @*, not outranks it (5.5)")
    func test_axisPatternPriority() throws {
        // attribute::node() is a node() node test, default priority -0.5 like @*,
        // not a name test (0). On the resulting tie the last template in document
        // order wins, so @* (declared last) applies, not attribute::node() which
        // was wrongly given priority 0 (Apache Xalan conflictres29, conflictres30).
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="doc/e/@a"/></out></xsl:template>
          <xsl:template match="attribute::node()">node</xsl:template>
          <xsl:template match="@*">star</xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<doc><e a=\"1\"/></doc>") == "<out>star</out>")
    }
}
