import Testing
@testable import PureXML

@Suite("XSLT xsl:sort case-order")
struct XSLTSortCaseOrderTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func sortStyle(_ caseOrder: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:for-each select="r/v"><xsl:sort select="." \(caseOrder)/><xsl:value-of select="."/><xsl:text>,</xsl:text></xsl:for-each></xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("case-order=upper-first puts uppercase before its lowercase twin")
    func test_upperFirst() throws {
        let out = try transform(sortStyle("case-order=\"upper-first\""), "<r><v>b</v><v>A</v><v>a</v><v>B</v></r>")
        #expect(out == "A,a,B,b,")
    }

    @Test("case-order=lower-first puts lowercase before its uppercase twin")
    func test_lowerFirst() throws {
        let out = try transform(sortStyle("case-order=\"lower-first\""), "<r><v>b</v><v>A</v><v>a</v><v>B</v></r>")
        #expect(out == "a,A,b,B,")
    }

    @Test("Without case-order the default codepoint order is unchanged")
    func test_default() throws {
        let out = try transform(sortStyle(""), "<r><v>b</v><v>A</v><v>a</v><v>B</v></r>")
        // Codepoint order: all uppercase (A,B) before all lowercase (a,b).
        #expect(out == "A,B,a,b,")
    }
}
