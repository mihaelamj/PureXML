import Testing
@testable import PureXML

/// XSLT 1.0 names every QName-keyed declaration by expanded name, so two
/// prefixes bound to the same namespace name the same thing. Declared with one
/// prefix and referenced with another (both bound to `urn:q`), each must still
/// resolve (Apache Xalan namedtemplate16, attribset48, idkey53).
@Suite("XSLT expanded-name QName declarations")
struct XSLTExpandedQNameTests {
    private let namespaces = "xmlns:a=\"urn:q\" xmlns:b=\"urn:q\""
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func run(_ body: String, _ extra: String = "") throws -> String {
        try PureXML.XSLT.transform(
            stylesheet: """
            <xsl:stylesheet version="1.0" \(xsl) \(namespaces) exclude-result-prefixes="a b">
              <xsl:output omit-xml-declaration="yes"/>
              \(extra)
              <xsl:template match="/"><out>\(body)</out></xsl:template>
            </xsl:stylesheet>
            """,
            source: "<doc><item k=\"K\">V</item></doc>",
        )
    }

    @Test("call-template matches a template named with a different same-namespace prefix")
    func test_namedTemplate() throws {
        let out = try run("<xsl:call-template name=\"a:t\"/>", "<xsl:template name=\"b:t\">T</xsl:template>")
        #expect(out == "<out>T</out>")
    }

    @Test("use-attribute-sets matches an attribute-set named with a different prefix")
    func test_attributeSet() throws {
        let out = try run(
            "<e xsl:use-attribute-sets=\"a:s\"/>",
            "<xsl:attribute-set name=\"b:s\"><xsl:attribute name=\"x\">1</xsl:attribute></xsl:attribute-set>",
        )
        #expect(out == "<out><e x=\"1\"/></out>")
    }

    @Test("key() matches an xsl:key named with a different prefix")
    func test_key() throws {
        let out = try run(
            "<xsl:value-of select=\"key('a:k', 'K')\"/>",
            "<xsl:key name=\"b:k\" match=\"item\" use=\"@k\"/>",
        )
        #expect(out == "<out>V</out>")
    }

    @Test("format-number matches an xsl:decimal-format named with a different prefix")
    func test_decimalFormat() throws {
        let out = try run(
            "<xsl:value-of select=\"format-number(5, '0!', 'a:f')\"/>",
            "<xsl:decimal-format name=\"b:f\" digit=\"!\"/>",
        )
        #expect(out == "<out>5</out>")
    }
}
