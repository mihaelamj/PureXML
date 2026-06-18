import Testing
@testable import PureXML

@Suite("XSLT xsl:namespace-alias")
struct XSLTNamespaceAliasTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("A literal element in the aliased namespace is rewritten to the result namespace")
    func test_rewrite() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:a="urn:from" xmlns:b="urn:to">
          <xsl:namespace-alias stylesheet-prefix="a" result-prefix="b"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><a:thing/></xsl:template>
        </xsl:stylesheet>
        """
        // The element's prefix is rewritten from the stylesheet alias to the
        // result, and the serializer declares the result namespace.
        #expect(try transform(style, "<x/>") == "<b:thing xmlns:b=\"urn:to\"/>")
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
        #expect(try transform(style, "<x/>") == "<plain xmlns:b=\"urn:to\"/>")
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
        // The aliased axsl: element is emitted as a literal xsl: element, not run.
        #expect(out.contains("xsl:value-of"))
        #expect(!out.contains("axsl"))
    }
}
