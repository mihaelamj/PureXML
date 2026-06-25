import Testing
@testable import PureXML

/// `xsl:number` level single and multiple rank a node among its parent's
/// matching children. That rank now comes from a per-parent-and-pattern cache
/// (built once) instead of rescanning the child list per numbered node. These
/// pin that the numbers are unchanged: the position among matching siblings for
/// the default and an explicit count, a partial-match count, and the
/// multiple-level path that numbers each matching ancestor.
@Suite("xsl:number level single and multiple")
struct XSLTNumberSingleTests {
    private func transform(_ source: String, template: String) throws -> String {
        let style = """
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="xml" indent="no"/>
          <xsl:template match="/"><out>\(template)</out></xsl:template>
        </xsl:stylesheet>
        """
        return try PureXML.XSLT.transform(stylesheet: style, source: source)
    }

    @Test("default and explicit count rank a node among its same-name siblings")
    func test_single() throws {
        let source = "<r><item/><item/><item/></r>"
        let template = #"<xsl:for-each select="//item"><n><xsl:number/></n></xsl:for-each>"#
        #expect(try transform(source, template: template).hasSuffix("<n>1</n><n>2</n><n>3</n></out>"))
        let explicit = #"<xsl:for-each select="//item"><n><xsl:number count="item"/></n></xsl:for-each>"#
        #expect(try transform(source, template: explicit).hasSuffix("<n>1</n><n>2</n><n>3</n></out>"))
    }

    @Test("a partial-match count numbers only the matching siblings")
    func test_partialMatch() throws {
        // The <other/> elements are interleaved but not counted, so the items
        // keep ranks 1, 2, 3 among the item siblings.
        let source = "<r><other/><item/><other/><item/><item/><other/></r>"
        let template = #"<xsl:for-each select="//item"><n><xsl:number count="item"/></n></xsl:for-each>"#
        #expect(try transform(source, template: template).hasSuffix("<n>1</n><n>2</n><n>3</n></out>"))
    }

    @Test("multiple level numbers each matching ancestor")
    func test_multiple() throws {
        let source = "<doc><sec><sec/><sec/></sec><sec/></doc>"
        // The innermost <sec> elements: the two inside the first sec are 1.1 and
        // 1.2; the last top-level sec is 2.
        let template = #"<xsl:for-each select="//sec[not(sec)]"><n><xsl:number level="multiple" count="sec" format="1.1"/></n></xsl:for-each>"#
        let out = try transform(source, template: template)
        #expect(out.hasSuffix("<n>1.1</n><n>1.2</n><n>2</n></out>"))
    }
}
