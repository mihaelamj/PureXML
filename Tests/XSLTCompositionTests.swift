import Testing
@testable import PureXML

/// Stylesheet composition behaviors of the xalan burn-down (#130): import
/// precedence and apply-imports scoping, relative include/import chains,
/// global variable scope and precedence, attribute-set definition merging,
/// xsl:copy namespace-node copying, and NCName:* name tests.
@Suite("XSLT composition and scoping")
struct XSLTCompositionTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    @Test("apply-imports searches only the current stylesheet's own imports (5.6)")
    func test_applyImportsScope() throws {
        let leaf = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="item"><leaf/></xsl:template>
        </xsl:stylesheet>
        """
        let sibling = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="item"><sibling><xsl:apply-imports/></sibling></xsl:template>
        </xsl:stylesheet>
        """
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="leaf.xsl"/>
          <xsl:import href="sibling.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//item"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<r><item>x</item></r>",
            documentLoader: { ["leaf.xsl": leaf, "sibling.xsl": sibling][$0] },
        )
        // sibling.xsl wins (later import); its apply-imports has no imports of
        // its own, so the built-in rule runs, not leaf.xsl's template.
        #expect(result == "<out><sibling>x</sibling></out>")
    }

    @Test("Include and import hrefs resolve against the including stylesheet's URI")
    func test_relativeIncludeChain() throws {
        let inner = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="item"><deep/></xsl:template>
        </xsl:stylesheet>
        """
        let middle = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:include href="inner.xsl"/>
        </xsl:stylesheet>
        """
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:include href="sub/middle.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//item"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<r><item/></r>",
            documentLoader: { ["sub/middle.xsl": middle, "sub/inner.xsl": inner][$0] },
        )
        #expect(result == "<out><deep/></out>")
    }

    @Test("A global variable sees earlier globals, call-template included")
    func test_globalSeesEarlierGlobals() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:param name="toto" select="'titi'"/>
          <xsl:variable name="tata"><xsl:call-template name="set"/></xsl:variable>
          <xsl:template match="/"><out><xsl:value-of select="$tata"/></out></xsl:template>
          <xsl:template name="set"><xsl:value-of select="$toto"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out>titi</out>")
    }

    @Test("Same-name globals resolve by import precedence, later sibling import winning")
    func test_globalImportPrecedence() throws {
        let first = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:param name="v" select="'first'"/></xsl:stylesheet>
        """
        let second = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:param name="v" select="'second'"/></xsl:stylesheet>
        """
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="first.xsl"/>
          <xsl:import href="second.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="$v"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<x/>",
            documentLoader: { ["first.xsl": first, "second.xsl": second][$0] },
        )
        #expect(result == "<out>second</out>")
    }

    @Test("NCName:* name tests match by namespace and outrank the bare wildcard")
    func test_prefixWildcard() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:p="urn:p">
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//@*"/></out></xsl:template>
          <xsl:template match="@*">w,</xsl:template>
          <xsl:template match="@p:*">q,</xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r xmlns:p=\"urn:p\" a=\"1\" p:b=\"2\"/>"
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: source) == "<out xmlns:p=\"urn:p\">w,q,</out>")
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

    @Test("id() resolves only DTD-declared ID attributes; no DTD means no IDs")
    func test_idRequiresDTD() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="id('c')"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let withDTD = """
        <!DOCTYPE doc [<!ELEMENT doc (e*)> <!ELEMENT e (#PCDATA)> <!ATTLIST e id ID #IMPLIED>]>
        <doc><e id="b">no</e><e id="c">yes</e></doc>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: withDTD) == "<out>yes</out>")
        let withoutDTD = "<doc><e id=\"c\">yes</e></doc>"
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: withoutDTD) == "<out></out>")
    }

    @Test("generate-id() is non-empty and distinct for attribute and namespace nodes")
    func test_generateIDNodeKinds() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/">
            <xsl:if test="generate-id(//e) != '' and generate-id(//e/@a) != '' and generate-id(//e/@a) != generate-id(//e)">distinct</xsl:if>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<r><e a=\"1\"/></r>") == "distinct")
    }

    @Test("Caller-supplied parameters override xsl:param defaults, not xsl:variable")
    func test_topLevelParameters() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:param name="p" select="'default'"/>
          <xsl:variable name="v" select="'fixed'"/>
          <xsl:template match="/"><out><xsl:value-of select="$p"/>-<xsl:value-of select="$v"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let overridden = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<x/>",
            parameters: ["p": "supplied", "v": "ignored"],
        )
        #expect(overridden == "<out>supplied-fixed</out>")
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out>default-fixed</out>")
    }

    @Test("An include or import cycle terminates instead of recursing forever")
    func test_compositionCycle() throws {
        let first = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:include href="b.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out/></xsl:template>
        </xsl:stylesheet>
        """
        let second = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:include href="a.xsl"/></xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: first,
            source: "<x/>",
            documentLoader: { ["a.xsl": first, "b.xsl": second][$0] },
        )
        #expect(result == "<out/>")
    }

    @Test("A diamond import stays legal: both sides load the shared sheet")
    func test_diamondImport() throws {
        let shared = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:template match="item">S</xsl:template></xsl:stylesheet>
        """
        let left = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:import href="shared.xsl"/></xsl:stylesheet>
        """
        let right = """
        <xsl:stylesheet version="1.0" \(xsl)><xsl:import href="shared.xsl"/><xsl:template match="item">R<xsl:apply-imports/></xsl:template></xsl:stylesheet>
        """
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:import href="left.xsl"/>
          <xsl:import href="right.xsl"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//item"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: style,
            source: "<r><item/></r>",
            documentLoader: { ["shared.xsl": shared, "left.xsl": left, "right.xsl": right][$0] },
        )
        // right.xsl wins (later import); its apply-imports reaches its own
        // imported copy of shared.xsl.
        #expect(result == "<out>RS</out>")
    }
}
