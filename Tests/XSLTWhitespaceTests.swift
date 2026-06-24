import Testing
@testable import PureXML

@Suite("XSLT strip-space / preserve-space")
struct XSLTWhitespaceTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("strip-space removes whitespace-only text nodes; a copy reflects it")
    func test_stripSpace() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:strip-space elements="a"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><xsl:copy-of select="a"/></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<a>\n  <b/>\n  <b/>\n</a>"
        // The indentation whitespace between <b/> elements is stripped.
        #expect(try transform(style, source) == "<a><b/><b/></a>")
    }

    @Test("Without strip-space the whitespace is preserved")
    func test_noStrip() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><xsl:copy-of select="a"/></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<a>\n  <b/>\n</a>"
        #expect(try transform(style, source).contains("\n  "))
    }

    @Test("preserve-space overrides strip-space for a named element")
    func test_preserveOverrides() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:strip-space elements="*"/>
          <xsl:preserve-space elements="keep"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><xsl:copy-of select="*"/></xsl:template>
        </xsl:stylesheet>
        """
        // strip-space="*" strips <drop>'s whitespace, but <keep> preserves its own.
        let stripped = try transform(style, "<drop>\n  <x/>\n</drop>")
        #expect(stripped == "<drop><x/></drop>")
        let kept = try transform(style, "<keep>\n  <x/>\n</keep>")
        #expect(kept.contains("\n  "))
    }

    @Test("xml:space=preserve on a source element keeps its whitespace despite strip-space")
    func test_xmlSpacePreserve() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:strip-space elements="a"/>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><xsl:copy-of select="a"/></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<a xml:space=\"preserve\">\n  <b/>\n</a>"
        #expect(try transform(style, source).contains("\n  "))
    }

    @Test("strip-space matches a namespace wildcard by namespace, not prefix")
    func test_namespaceWildcard() throws {
        // strip-space `p:*` strips elements in p's namespace. The source binds the
        // same namespace to a different prefix (q), which must still match, while
        // an element in another namespace is preserved (Apache Xalan whitespace06,
        // whitespace07).
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:p="urn:n1" xmlns:s="urn:n2" exclude-result-prefixes="p s">
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:strip-space elements="p:*"/>
          <xsl:template match="/"><out><xsl:value-of select="string-length(doc/p:a)"/>,<xsl:value-of select="string-length(doc/s:b)"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<doc xmlns:q=\"urn:n1\" xmlns:r=\"urn:n2\"><q:a>  </q:a><r:b>  </r:b></doc>"
        #expect(try transform(style, source) == "<out>0,2</out>")
    }

    @Test("xml:space=preserve in the stylesheet keeps a literal element's whitespace (3.4)")
    func test_xmlSpacePreserveInStylesheet() throws {
        // A literal result element with xml:space="preserve" keeps its
        // whitespace-only content; xml:space="default" strips it, as does no
        // xml:space at all (Apache Xalan whitespace20).
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><r><a xml:space="preserve"> </a><b xml:space="default"> </b><c> </c></r></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<r><a xml:space=\"preserve\"> </a><b xml:space=\"default\"/><c/></r>")
    }
}
