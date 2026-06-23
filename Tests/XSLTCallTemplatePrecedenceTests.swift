import Testing
@testable import PureXML

/// `xsl:call-template` selects its target by import precedence (XSLT 1.0
/// section 6), not by the position of the definition in the flattened
/// stylesheet. An included template carries the including unit's precedence,
/// so it outranks a same-name template from an import (Apache Xalan
/// namedtemplate17-19, namespace13).
@Suite("XSLT call-template precedence")
struct XSLTCallTemplatePrecedenceTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    @Test("An include outranks a same-name import")
    func test_includeOutranksImport() throws {
        let imported = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template name="t">IMPORT</xsl:template>
        </xsl:stylesheet>
        """
        let included = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template name="t">INCLUDE</xsl:template>
        </xsl:stylesheet>
        """
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="imp.xsl"/>
          <xsl:include href="inc.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:call-template name="t"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<x/>",
            documentLoader: { ["imp.xsl": imported, "inc.xsl": included][$0] },
        )
        // The included template (the including unit's precedence) wins over the
        // imported one, which folds in first by position.
        #expect(result == "<out>INCLUDE</out>")
    }
}
