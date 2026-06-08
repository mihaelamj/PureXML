@testable import PureXML
import Testing

@Suite("XSLT transform")
struct XSLTTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
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
