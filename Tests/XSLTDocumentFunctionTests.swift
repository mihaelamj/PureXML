@testable import PureXML
import Testing

@Suite("XSLT document() fragments and base-URI resolution")
struct XSLTDocumentFunctionTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String, baseURI: String = "", loader: @escaping (String) -> String?) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source, documentLoader: loader, baseURI: baseURI)
    }

    private let external = "<doc><section id=\"s1\">first</section><section id=\"s2\">second</section></doc>"

    @Test("document() with no fragment loads the whole document")
    func test_wholeDocument() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="count(document('ext.xml')//section)"/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>") { $0 == "ext.xml" ? external : nil }
        #expect(out == "2")
    }

    @Test("document() with an xpointer fragment selects a subset")
    func test_xpointerFragment() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="document('ext.xml#xpointer(/doc/section[2])')"/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>") { $0 == "ext.xml" ? external : nil }
        #expect(out == "second")
    }

    @Test("A relative document() URI is resolved against the base URI")
    func test_baseURI() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="count(document('ext.xml')//section)"/></xsl:template>
        </xsl:stylesheet>
        """
        var requested: [String] = []
        let out = try transform(style, "<x/>", baseURI: "http://example.org/docs/") { uri in
            requested.append(uri)
            return uri == "http://example.org/docs/ext.xml" ? external : nil
        }
        #expect(out == "2")
        #expect(requested.contains("http://example.org/docs/ext.xml"))
    }

    @Test("document() with a node-set argument unions the loaded documents")
    func test_nodeSetArgument() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="count(document(//ref)//section)"/></xsl:template>
        </xsl:stylesheet>
        """
        let source = "<x><ref>a.xml</ref><ref>b.xml</ref></x>"
        let out = try transform(style, source) { uri in
            switch uri {
            case "a.xml": "<doc><section>1</section></doc>"
            case "b.xml": "<doc><section>2</section><section>3</section></doc>"
            default: nil
            }
        }
        #expect(out == "3")
    }
}
