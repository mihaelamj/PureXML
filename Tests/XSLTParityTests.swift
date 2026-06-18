import Testing
@testable import PureXML

@Suite("XSLT keys, numbering, output")
struct XSLTParityTests {
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

    @Test("xsl:key indexes nodes and key() retrieves them")
    func test_key() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:key name="byCat" match="item" use="@cat"/>
          <xsl:template match="/">
            <out><xsl:for-each select="key('byCat', 'fruit')"><n><xsl:value-of select="."/></n></xsl:for-each></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let source = "<r><item cat=\"fruit\">apple</item><item cat=\"veg\">pea</item><item cat=\"fruit\">pear</item></r>"
        #expect(try transform(stylesheet, source) == "<out><n>apple</n><n>pear</n></out>")
    }

    @Test("format-number renders per the picture string")
    func test_formatNumber() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out>
              <a><xsl:value-of select="format-number(1234.5, '#,##0.00')"/></a>
              <b><xsl:value-of select="format-number(0.25, '0%')"/></b>
            </out>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<x/>") == "<out><a>1,234.50</a><b>25%</b></out>")
    }

    @Test("xsl:number generates the position of the context node")
    func test_number() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/"><out><xsl:apply-templates select="r/i"/></out></xsl:template>
          <xsl:template match="i"><n><xsl:number format="i"/></n></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<r><i/><i/><i/></r>") == "<out><n>i</n><n>ii</n><n>iii</n></out>")
    }

    @Test("document() loads external source through the injected loader")
    func test_document() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out><xsl:value-of select="document('ext.xml')/data/v"/></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: stylesheet,
            source: "<x/>",
            documentLoader: { uri in uri == "ext.xml" ? "<data><v>loaded</v></data>" : nil },
        )
        #expect(result == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<out>loaded</out>")
    }

    @Test("xsl:comment and xsl:processing-instruction emit their nodes")
    func test_commentAndPI() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="/">
            <out><xsl:comment>note</xsl:comment><xsl:processing-instruction name="go">run</xsl:processing-instruction></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<x/>") == "<out><!--note--><?go run?></out>")
    }

    @Test("xsl:output text method drops markup and yields character data")
    func test_outputText() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><a>x</a><b>y</b></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(stylesheet, "<r/>") == "xy")
    }

    @Test("xsl:output controls the XML declaration and indentation")
    func test_outputDeclaration() throws {
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:output omit-xml-declaration="no" encoding="UTF-8"/>
          <xsl:template match="/"><out>z</out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: stylesheet, source: "<r/>") == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<out>z</out>")
    }

    @Test("xsl:include folds in another stylesheet's templates")
    func test_include() throws {
        let included = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="i"><hit><xsl:value-of select="."/></hit></xsl:template>
        </xsl:stylesheet>
        """
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:include href="lib.xsl"/>
          <xsl:template match="/"><out><xsl:apply-templates select="r/i"/></out></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: stylesheet,
            source: "<r><i>a</i></r>",
            documentLoader: { $0 == "lib.xsl" ? included : nil },
        )
        #expect(result == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<out><hit>a</hit></out>")
    }

    @Test("xsl:import is overridden by the importing stylesheet")
    func test_importPrecedence() throws {
        let base = """
        <xsl:stylesheet \(xsl)>
          <xsl:template match="i"><low><xsl:value-of select="."/></low></xsl:template>
        </xsl:stylesheet>
        """
        let stylesheet = """
        <xsl:stylesheet \(xsl)>
          <xsl:import href="base.xsl"/>
          <xsl:template match="/"><out><xsl:apply-templates select="r/i"/></out></xsl:template>
          <xsl:template match="i"><high><xsl:value-of select="."/></high></xsl:template>
        </xsl:stylesheet>
        """
        let result = try PureXML.XSLT.transform(
            stylesheet: stylesheet,
            source: "<r><i>a</i></r>",
            documentLoader: { $0 == "base.xsl" ? base : nil },
        )
        #expect(result == "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<out><high>a</high></out>")
    }
}
