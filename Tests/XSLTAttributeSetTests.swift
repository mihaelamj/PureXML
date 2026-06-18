import Testing
@testable import PureXML

@Suite("XSLT xsl:attribute-set")
struct XSLTAttributeSetTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("use-attribute-sets applies a named set to a literal element")
    func test_literalUseAttributeSets() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:attribute-set name="common">
            <xsl:attribute name="class">box</xsl:attribute>
          </xsl:attribute-set>
          <xsl:template match="/"><div xsl:use-attribute-sets="common"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<div class=\"box\"/>")
    }

    @Test("An element's own attribute overrides one from the attribute set")
    func test_ownOverrides() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:attribute-set name="s"><xsl:attribute name="class">base</xsl:attribute></xsl:attribute-set>
          <xsl:template match="/"><div xsl:use-attribute-sets="s" class="override"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<div class=\"override\"/>")
    }

    @Test("xsl:element honors use-attribute-sets")
    func test_xslElement() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:attribute-set name="s"><xsl:attribute name="id">1</xsl:attribute></xsl:attribute-set>
          <xsl:template match="/"><xsl:element name="p" use-attribute-sets="s"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<p id=\"1\"/>")
    }

    @Test("An attribute set may include another set")
    func test_nestedSets() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:attribute-set name="a"><xsl:attribute name="a">1</xsl:attribute></xsl:attribute-set>
          <xsl:attribute-set name="b" use-attribute-sets="a"><xsl:attribute name="b">2</xsl:attribute></xsl:attribute-set>
          <xsl:template match="/"><x xsl:use-attribute-sets="b"/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>")
        #expect(out.contains("a=\"1\""))
        #expect(out.contains("b=\"2\""))
    }
}
