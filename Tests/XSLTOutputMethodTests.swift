@testable import PureXML
import Testing

/// The output-method behaviors of XSLT 1.0 section 16 added in the xalan
/// burn-down (#130): disable-output-escaping (including its 16.4 fragment
/// rule and the marker-safety gate), CDATA "]]>" splitting, the simplified
/// stylesheet syntax, the html default method with META injection, key()
/// inside document() trees, and the attribute-start following/preceding axes.
@Suite("XSLT output methods and runtime corners")
struct XSLTOutputMethodTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    @Test("disable-output-escaping writes text through unescaped")
    func test_disableOutputEscaping() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:text disable-output-escaping="yes">&lt;P&gt;&amp;nbsp;&lt;/P&gt;</xsl:text></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out><P>&nbsp;</P></out>")
    }

    @Test("disable-output-escaping does not survive a fragment round-trip (16.4)")
    func test_rawTextFragmentRoundTrip() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/">
            <out>
              <xsl:variable name="held"><xsl:text disable-output-escaping="yes">a &lt;b&gt; c</xsl:text></xsl:variable>
              <xsl:value-of select="$held"/>
            </out>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out>a &lt;b&gt; c</out>")
    }

    @Test("Source text holding the private-use marker characters is untouched")
    func test_markerCharactersInSource() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="d"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<d>a\u{E000}&lt;kept&gt;\u{E001}b</d>"
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: source) == "<out>a\u{E000}&lt;kept&gt;\u{E001}b</out>")
    }

    @Test("cdata-section-elements split ]]> across section boundaries")
    func test_cdataTerminatorSplitting() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes" cdata-section-elements="example"/>
          <xsl:template match="/"><out><example><xsl:text>]]&gt;</xsl:text></example></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out><example><![CDATA[]]]]><![CDATA[>]]></example></out>")
    }

    @Test("A literal result element with xsl:version is a one-template stylesheet (2.3)")
    func test_simplifiedSyntax() throws {
        let style = """
        <out xsl:version="1.0" \(xsl)>value: <xsl:value-of select="doc/v"/></out>
        """
        let result = try PureXML.XSLT.transform(stylesheet: style, source: "<doc><v>7</v></doc>")
        #expect(result.hasSuffix("<out>value: 7</out>"))
    }

    @Test("A null-namespace html root selects the html method and gains META (16.1/16.2)")
    func test_htmlDefaultMethod() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="/"><HTML><HEAD><TITLE>t</TITLE></HEAD><BODY><BR/></BODY></HTML></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
        #expect(result == "<HTML><HEAD><META http-equiv=\"Content-Type\" content=\"text/html; charset=UTF-8\"><TITLE>t</TITLE></HEAD><BODY><BR></BODY></HTML>")
    }

    @Test("key() indexes the current node's own document, document() trees included")
    func test_keyPerDocument() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:key name="k" match="item" use="@id"/>
          <xsl:template match="/">
            <out>
              <xsl:for-each select="document('other.xml')">
                <xsl:value-of select="key('k', 'b')"/>
              </xsl:for-each>
            </out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<doc><item id=\"b\">local</item></doc>",
            documentLoader: { $0 == "other.xml" ? "<doc><item id=\"b\">external</item></doc>" : nil },
        )
        #expect(result == "<out>external</out>")
    }

    @Test("following and preceding work from attribute starts")
    func test_axesFromAttributes() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/">
            <out>
              <f><xsl:for-each select="//b/@m/following::*"><xsl:value-of select="name()"/><xsl:text> </xsl:text></xsl:for-each></f>
              <p><xsl:for-each select="//b/@m/preceding::*"><xsl:value-of select="name()"/><xsl:text> </xsl:text></xsl:for-each></p>
            </out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r><a/><b m=\"1\"><inner/></b><c/></r>"
        // Document order places the attribute after b and before b's children,
        // so following includes inner and c; preceding holds a only (r is an
        // ancestor).
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: source) == "<out><f>inner c </f><p>a </p></out>")
    }

    @Test("Same-name attribute sets merge as ordered definitions (7.1.4)")
    func test_attributeSetMerge() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:attribute-set name="child" use-attribute-sets="alice">
            <xsl:attribute name="follow">yellowbrickroad</xsl:attribute>
            <xsl:attribute name="hole">shallow</xsl:attribute>
          </xsl:attribute-set>
          <xsl:attribute-set name="child" use-attribute-sets="rabbit">
            <xsl:attribute name="follow">theleader</xsl:attribute>
          </xsl:attribute-set>
          <xsl:attribute-set name="rabbit"><xsl:attribute name="hole">deep</xsl:attribute></xsl:attribute-set>
          <xsl:attribute-set name="alice"><xsl:attribute name="alice">ondrugs</xsl:attribute></xsl:attribute-set>
          <xsl:template match="/"><out xsl:use-attribute-sets="child"/></xsl:template>
        </xsl:stylesheet>
        """
        // The later definition expands after the earlier one (its used set
        // included), so its hole=deep and follow=theleader win.
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
            == "<out alice=\"ondrugs\" follow=\"theleader\" hole=\"deep\"/>")
    }

    @Test("xsl:copy carries the source element's in-scope namespace nodes (7.5)")
    func test_copyNamespaceNodes() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="inner"><xsl:copy/></xsl:template>
          <xsl:template match="/"><out><xsl:apply-templates select="//inner"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r xmlns:a=\"urn:a\"><inner xmlns:b=\"urn:b\"/></r>"
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: source)
            == "<out><inner xmlns:a=\"urn:a\" xmlns:b=\"urn:b\"/></out>")
    }

    @Test("html boolean attributes minimize when the value repeats the name")
    func test_htmlBooleanAttributes() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="html"/>
          <xsl:template match="/"><Form><Input Type="checkbox" CHECKED="CHECKED"/><Input Type="text" Value="CHECKED"/></Form></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
            == "<Form><Input Type=\"checkbox\" CHECKED><Input Type=\"text\" Value=\"CHECKED\"></Form>")
    }

    @Test("Stylesheet and source entities resolve through the document loader")
    func test_loaderEntityResolution() throws {
        let style = """
        <?xml version="1.0"?>
        <!DOCTYPE xsl:stylesheet SYSTEM "ents.dtd">
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:copy-of select="'a&aelig;b'"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<x/>",
            documentLoader: { $0 == "ents.dtd" ? "<!ENTITY aelig \"&#230;\">" : nil },
        )
        #expect(result == "<out>a\u{E6}b</out>")
    }
}
