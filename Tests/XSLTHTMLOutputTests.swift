import Testing
@testable import PureXML

@Suite("XSLT method=html output")
struct XSLTHTMLOutputTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func htmlStyle(_ body: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="html"/>
          <xsl:template match="/">\(body)</xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("A void element is emitted without a self-closing slash")
    func test_voidElement() throws {
        let out = try transform(htmlStyle("<br/>"), "<x/>")
        #expect(out == "<br>")
    }

    @Test("A non-void empty element keeps an explicit end tag")
    func test_nonVoid() throws {
        let out = try transform(htmlStyle("<div/>"), "<x/>")
        #expect(out == "<div></div>")
    }

    @Test("Raw-text element content is not escaped")
    func test_rawText() throws {
        let out = try transform(htmlStyle("<script>if (a &lt; b) x()</script>"), "<x/>")
        #expect(out.contains("if (a < b) x()"))
        #expect(!out.contains("&lt;"))
    }

    @Test("The html method leaves < and > literal in an attribute value")
    func test_attributeAngleBrackets() throws {
        // XSLT 1.0 16.2: the html output method does not escape `<` in an
        // attribute value (nor `>`), unlike the xml method. `&` and `"` still
        // escape (Apache Xalan output49, output74).
        let out = try transform(htmlStyle("<a title=\"&lt;x>&amp;&quot;\">t</a>"), "<x/>")
        #expect(out == "<a title=\"<x>&amp;&quot;\">t</a>")
    }

    @Test("The xml method still escapes < in an attribute value")
    func test_xmlAttributeStillEscapes() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><a title="&lt;x>">t</a></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<a title=\"&lt;x&gt;\">t</a>")
    }

    @Test("the html method percent-escapes non-ASCII and control chars in URI-valued attributes")
    func test_uriAttributeEscaping() throws {
        // XSLT 1.0 16.2 / HTML 4.01 B.2.1: a URI-valued attribute (cite, href,
        // src, ...) percent-escapes non-ASCII (the UTF-8 bytes) and control/space,
        // keeping `"` and `&` as entities; a non-URI attribute (title) keeps its
        // ordinary html escaping. Apache Xalan output32.
        let out = try transform(
            htmlStyle("<q cite=\"b&#235;.xml\" title=\"b&#235;\" href=\"a b&amp;c\"/>"), "<x/>",
        )
        #expect(out == "<q cite=\"b%C3%AB.xml\" title=\"b&euml;\" href=\"a%20b&amp;c\"></q>")
    }

    @Test("URI-attribute percent-escaping is idempotent")
    func test_uriEscapingIdempotent() throws {
        // A space becomes %20 once; an already-escaped value is stable because a
        // literal `%` is left as is (so a parse-serialize round-trip converges).
        #expect(try transform(htmlStyle("<a href=\"x y\"/>"), "<x/>") == "<a href=\"x%20y\"></a>")
        #expect(try transform(htmlStyle("<a href=\"x%20y\"/>"), "<x/>") == "<a href=\"x%20y\"></a>")
    }

    @Test("the html method serializes a namespaced element as XML, not HTML")
    func test_namespacedElementAsXML() throws {
        // XSLT 1.0 16.2: an element whose expanded-name has a non-null namespace
        // URI is output as XML (empty elements self-close, the namespace is
        // declared once), not HTML; a null-namespace element stays HTML (see
        // test_voidElement). The html serializer otherwise left empty namespaced
        // elements unclosed and repeated xmlns on every element.
        let out = try transform(htmlStyle("<svg xmlns=\"urn:svg\"><rect/><g><circle/></g></svg>"), "<x/>")
        #expect(out == "<svg xmlns=\"urn:svg\"><rect/><g><circle/></g></svg>")
    }

    @Test("The XML output method still self-closes empty elements")
    func test_xmlStillSelfCloses() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><br/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<br/>")
    }
}
