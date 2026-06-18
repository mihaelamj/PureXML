import Testing
@testable import PureXML

/// Namespaced name creation and result-tree namespace fixup (#130):
/// xsl:attribute/xsl:element honor the namespace attribute and resolve
/// prefixed names against the stylesheet's declarations, xsl:copy applies
/// use-attribute-sets, and the serializer declares every namespace a created
/// name carries, generating prefixes when needed.
@Suite("XSLT created names")
struct XSLTCreatedNamesTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    @Test("xsl:attribute with a namespace attribute generates a declared prefix")
    func test_attributeNamespace() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:attribute name="a" namespace="urn:n">v</xsl:attribute></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
        #expect(result == "<out ns0:a=\"v\" xmlns:ns0=\"urn:n\"/>")
    }

    @Test("A prefixed xsl:attribute name resolves against stylesheet declarations")
    func test_attributePrefix() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:p="urn:p">
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:attribute name="p:a">v</xsl:attribute></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
        #expect(result == "<out xmlns:p=\"urn:p\" p:a=\"v\"/>")
    }

    @Test("xsl:copy applies use-attribute-sets")
    func test_copyAttributeSets() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:attribute-set name="s"><xsl:attribute name="color">black</xsl:attribute></xsl:attribute-set>
          <xsl:template match="foo"><xsl:copy use-attribute-sets="s"/></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(stylesheet: style, source: "<foo/>")
        #expect(result == "<foo color=\"black\"/>")
    }
}
