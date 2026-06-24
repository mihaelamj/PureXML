import Testing
@testable import PureXML

@Suite("XSLT xsl:namespace-alias")
struct XSLTNamespaceAliasTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("A literal element in the aliased namespace keeps its prefix, with the result namespace")
    func test_rewrite() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:a="urn:from" xmlns:b="urn:to">
          <xsl:namespace-alias stylesheet-prefix="a" result-prefix="b"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><a:thing/></xsl:template>
        </xsl:stylesheet>
        """
        // 7.1.1: the literal prefix `a` is kept and only its namespace URI is
        // remapped to the result namespace; the result-prefix `b` selects the
        // namespace, it is not adopted as the output prefix (Apache Xalan
        // namespace19, namespace23, namespace24, namespace35, namespace113).
        #expect(try transform(style, "<x/>") == "<a:thing xmlns:a=\"urn:to\" xmlns:b=\"urn:to\"/>")
    }

    @Test("A non-aliased literal element still copies in-scope declarations")
    func test_notAliased() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:a="urn:from" xmlns:b="urn:to">
          <xsl:namespace-alias stylesheet-prefix="a" result-prefix="b"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><plain/></xsl:template>
        </xsl:stylesheet>
        """
        // Both in-scope namespaces are copied; the aliased `a` keeps its prefix
        // with its URI remapped to the result namespace, alongside `b`.
        #expect(try transform(style, "<x/>") == "<plain xmlns:a=\"urn:to\" xmlns:b=\"urn:to\"/>")
    }

    @Test("namespace-alias can produce literal xsl: elements (stylesheet generation)")
    func test_generateXSL() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:axsl="urn:alias">
          <xsl:namespace-alias stylesheet-prefix="axsl" result-prefix="xsl"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><axsl:value-of select="."/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>")
        // The aliased axsl: element keeps its prefix but is bound to the XSLT
        // namespace, so it is a literal xsl:value-of (axsl maps to Transform),
        // not run as an instruction.
        #expect(out == "<axsl:value-of xmlns:axsl=\"http://www.w3.org/1999/XSL/Transform\" select=\".\"/>")
    }
}
