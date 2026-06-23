import Testing
@testable import PureXML

@Suite("XSLT transform")
struct XSLTTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        // These cases assert result markup, not the prolog: drop the
        // spec-default XML declaration the xml method now writes.
        let output = try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
        guard output.hasPrefix("<?xml ") else { return output }
        guard let end = output.range(of: "?>") else { return output }
        var body = String(output[end.upperBound...])
        if body.hasPrefix("\n") { body.removeFirst() }
        return body
    }

    @Test("call-template passes with-param values, falling back to param defaults")
    func test_callTemplateParams() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out>
              <xsl:call-template name="greet"><xsl:with-param name="who" select="'Ada'"/></xsl:call-template>
              <xsl:call-template name="greet"/>
            </out>
          </xsl:template>
          <xsl:template name="greet">
            <xsl:param name="who" select="'world'"/>
            <hi><xsl:value-of select="$who"/></hi>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<x/>") == "<out><hi>Ada</hi><hi>world</hi></out>")
    }

    @Test("apply-templates passes parameters to the matched template")
    func test_applyTemplatesParams() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <xsl:apply-templates select="r/i"><xsl:with-param name="p" select="'X'"/></xsl:apply-templates>
          </xsl:template>
          <xsl:template match="i">
            <xsl:param name="p" select="'-'"/>
            <v><xsl:value-of select="$p"/><xsl:value-of select="."/></v>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<r><i>a</i><i>b</i></r>") == "<v>Xa</v><v>Xb</v>")
    }

    @Test("Modes route nodes to mode-specific templates")
    func test_modes() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <toc><xsl:apply-templates select="doc/h" mode="toc"/></toc>
            <body><xsl:apply-templates select="doc/h"/></body>
          </xsl:template>
          <xsl:template match="h" mode="toc"><li><xsl:value-of select="."/></li></xsl:template>
          <xsl:template match="h"><h1><xsl:value-of select="."/></h1></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<doc><h>A</h><h>B</h></doc>"
        #expect(try transform(stylesheet, source) == "<toc><li>A</li><li>B</li></toc><body><h1>A</h1><h1>B</h1></body>")
    }

    @Test("A mode is matched by expanded name: prefixes sharing a namespace name the same mode")
    func test_modeMatchedByExpandedName() throws {
        // foo and moo are both bound to urn:m, so apply-templates mode="foo:m"
        // selects the template with mode="moo:m" (XSLT 1.0 5.7, Xalan modes16).
        let stylesheet = """
        <xsl:stylesheet \(xsl) xmlns:foo="urn:m" xmlns:moo="urn:m" exclude-result-prefixes="foo moo">
          <xsl:template match="/"><out><xsl:apply-templates select="doc/a" mode="foo:m"/></out></xsl:template>
          <xsl:template match="a" mode="moo:m">matched</xsl:template>
          <xsl:template match="a">unmatched</xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<doc><a/></doc>") == "<out>matched</out>")
    }

    @Test("xsl:copy of the root with use-attribute-sets adds the attributes to the enclosing element")
    func test_copyRootWithAttributeSets() throws {
        // Copying the root makes no element of its own, so the attribute-set
        // attributes join the enclosing <out> (XSLT 1.0 7.5, Xalan attribset29).
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:attribute-set name="s"><xsl:attribute name="a">1</xsl:attribute></xsl:attribute-set>
          <xsl:template match="/"><out><xsl:copy use-attribute-sets="s"/></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<x/>") == "<out a=\"1\"/>")
    }

    @Test("xsl:element with an unusable name passes its content through")
    func test_elementInvalidNamePassThrough() throws {
        func out(_ name: String) throws -> String {
            try transform("""
            <xsl:stylesheet \(xsl)>
              <xsl:output omit-xml-declaration="yes"/>
              <xsl:template match="/"><out><xsl:element name="\(name)"><yyy/></xsl:element></out></xsl:template>
            </xsl:stylesheet>
            """, "<x/>")
        }
        // An undeclared prefix or non-QName name is unusable; the recovery emits
        // the content without the wrapper element (XSLT 1.0 7.1.2, Xalan namespace40/43).
        #expect(try out("none:foo") == "<out><yyy/></out>") // undeclared prefix
        #expect(try out("this is bad") == "<out><yyy/></out>") // not an NCName
        #expect(try out("good") == "<out><good><yyy/></good></out>") // a valid name still wraps
    }

    @Test("xsl:copy-of carries an element's inherited namespace nodes")
    func test_copyOfInheritedNamespaces() throws {
        // The copied <inner> inherits xmlns:ped from the root, with no ped-prefixed
        // name of its own, so copy-of must still carry the ped namespace node
        // (XSLT 1.0 11.3, Apache Xalan copy09).
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:copy-of select="root/inner"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<root xmlns:ped=\"urn:ped\"><inner xmlns:bdd=\"urn:bdd\"/></root>"
        #expect(try transform(stylesheet, source) == "<out><inner xmlns:bdd=\"urn:bdd\" xmlns:ped=\"urn:ped\"/></out>")
    }

    @Test("xsl:processing-instruction and xsl:comment keep only text-node content")
    func test_piCommentIgnoreNonTextContent() throws {
        // Content that creates a non-text node (here a copied element) is ignored
        // with its content, not flattened to its string value (XSLT 1.0 7.4/7.6,
        // Apache Xalan copy60), so only the leading text node survives.
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/doc"><out><xsl:processing-instruction name="pi"><xsl:copy-of select="node()"/></xsl:processing-instruction></out></xsl:template>
        </xsl:stylesheet>
        """
        // doc = text "foo" then an element; the element node is dropped.
        #expect(try transform(stylesheet, "<doc>foo<a>bar</a></doc>") == "<out><?pi foo?></out>")
    }

    @Test("xsl:attribute keeps only text-node content (errata E27)")
    func test_attributeIgnoresNonTextContent() throws {
        // a = "T1" + <b>BBBB</b> + "T2"; the <b> element node is ignored with its
        // content, so the attribute is "T1T2", not "T1BBBBT2" (Xalan copy58).
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/docs"><out><xsl:attribute name="attr1"><xsl:copy-of select="a/node()"/></xsl:attribute></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<docs><a>T1<b>BBBB</b>T2</a></docs>") == "<out attr1=\"T1T2\"/>")
    }

    @Test("Whitespace around a CDATA section in a template is preserved")
    func test_literalWhitespaceAroundCData() throws {
        // Text and CDATA coalesce into one node, so " <![CDATA[test]]> " is the
        // non-whitespace node " test " and its spaces survive stripping, while a
        // purely whitespace run between elements is still dropped (Xalan
        // whitespace13).
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out> <![CDATA[test]]> </out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<x/>") == "<out> test </out>")
    }

    @Test("A match pattern predicate sees top-level variables")
    func test_patternReferencesGlobalVariable() throws {
        // foo[. > $screen] matches only foo elements over the global threshold
        // (XSLT 1.0 5.2: a pattern predicate sees the global variables; Xalan
        // match14). Without them the predicate fails and nothing matches.
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:variable name="screen" select="7"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/doc"><out><xsl:apply-templates/></out></xsl:template>
          <xsl:template match="foo[. &gt; $screen]"><xsl:value-of select="@n"/>:over,</xsl:template>
          <xsl:template match="*"><xsl:value-of select="@n"/>:under,</xsl:template>
        </xsl:stylesheet>
        """
        let source = "<doc><foo n=\"a\">8</foo><foo n=\"b\">5</foo><foo n=\"c\">9</foo></doc>"
        #expect(try transform(stylesheet, source) == "<out>a:over,b:under,c:over,</out>")
    }

    @Test("The identity transform reproduces the input")
    func test_identity() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="*">
            <xsl:copy><xsl:copy-of select="@*"/><xsl:apply-templates/></xsl:copy>
          </xsl:template>
        </xsl:stylesheet>
        """
        let source = "<a id=\"1\"><b>text</b><c/></a>"
        #expect(try transform(stylesheet, source) == source)
    }

    @Test("value-of outputs the string value of an expression")
    func test_valueOf() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <result><xsl:value-of select="doc/name"/></result>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<doc><name>Ada</name></doc>") == "<result>Ada</result>")
    }

    @Test("apply-templates dispatches to matching templates")
    func test_applyTemplates() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/"><ul><xsl:apply-templates select="list/item"/></ul></xsl:template>
          <xsl:template match="item"><li><xsl:value-of select="."/></li></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<list><item>a</item><item>b</item></list>"
        #expect(try transform(stylesheet, source) == "<ul><li>a</li><li>b</li></ul>")
    }

    @Test("for-each iterates a node-set")
    func test_forEach() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out><xsl:for-each select="r/x"><v><xsl:value-of select="@n"/></v></xsl:for-each></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r><x n=\"1\"/><x n=\"2\"/></r>"
        #expect(try transform(stylesheet, source) == "<out><v>1</v><v>2</v></out>")
    }

    @Test("if and choose select conditionally")
    func test_conditionals() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <xsl:for-each select="nums/n">
              <xsl:choose>
                <xsl:when test=". > 0"><pos><xsl:value-of select="."/></pos></xsl:when>
                <xsl:otherwise><neg/></xsl:otherwise>
              </xsl:choose>
            </xsl:for-each>
          </xsl:template>
        </xsl:stylesheet>
        """
        let source = "<nums><n>5</n><n>-3</n></nums>"
        #expect(try transform(stylesheet, source) == "<pos>5</pos><neg/>")
    }

    @Test("xsl:attribute and xsl:element build the result dynamically")
    func test_dynamicElement() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <xsl:element name="box"><xsl:attribute name="w"><xsl:value-of select="size/@w"/></xsl:attribute></xsl:element>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<size w=\"10\"/>") == "<box w=\"10\"/>")
    }

    @Test("xsl:sort orders the selected nodes")
    func test_sort() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out><xsl:apply-templates select="r/n"><xsl:sort select="." data-type="number"/></xsl:apply-templates></out>
          </xsl:template>
          <xsl:template match="n"><v><xsl:value-of select="."/></v></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r><n>3</n><n>1</n><n>2</n></r>"
        #expect(try transform(stylesheet, source) == "<out><v>1</v><v>2</v><v>3</v></out>")
    }

    @Test("Attribute value templates substitute expressions")
    func test_attributeValueTemplate() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/"><a href="id-{doc/@k}">link</a></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<doc k=\"7\"/>") == "<a href=\"id-7\">link</a>")
    }
}
