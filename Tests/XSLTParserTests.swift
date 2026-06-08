@testable import PureXML
import Testing

@Suite("XSLT parser")
struct XSLTParserTests {
    private let stylesheet = """
    <xsl:stylesheet xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
      <xsl:template match="/">
        <html><body><xsl:apply-templates/></body></html>
      </xsl:template>
      <xsl:template match="book/title" priority="2">
        <h1><xsl:value-of select="."/></h1>
      </xsl:template>
      <xsl:template match="*">
        <xsl:for-each select="item"><xsl:value-of select="@id"/></xsl:for-each>
      </xsl:template>
    </xsl:stylesheet>
    """

    @Test("Templates are extracted with their match and priority")
    func test_templates() throws {
        let sheet = try PureXML.XSLT.XSLTParser.parse(stylesheet)
        #expect(sheet.templates.count == 3)
        #expect(sheet.templates.map(\.match) == ["/", "book/title", "*"])
        #expect(sheet.templates[1].priority == 2)
    }

    @Test("Default priorities follow the XSLT rules")
    func test_defaultPriority() {
        let priority = PureXML.XSLT.XSLTParser.defaultPriority
        #expect(priority("book") == 0)
        #expect(priority("book/title") == 0.5)
        #expect(priority("*") == -0.5)
        #expect(priority("ns:*") == -0.25)
    }

    @Test("A literal result element carries its children and apply-templates")
    func test_literalElement() throws {
        let sheet = try PureXML.XSLT.XSLTParser.parse(stylesheet)
        guard case let .literalElement(name, _, _, body) = sheet.templates[0].body.first else {
            Issue.record("expected a literal element")
            return
        }
        #expect(name.localName == "html")
        #expect(!body.isEmpty)
    }

    @Test("for-each and value-of are parsed")
    func test_forEach() throws {
        let sheet = try PureXML.XSLT.XSLTParser.parse(stylesheet)
        guard case let .forEach(select, _, body) = sheet.templates[2].body.first else {
            Issue.record("expected for-each")
            return
        }
        #expect(select == "item")
        guard case .valueOf(select: "@id") = body.first else {
            Issue.record("expected value-of")
            return
        }
    }

    @Test("Attribute value templates split literals and expressions")
    func test_valueTemplate() {
        let parts = PureXML.XSLT.XSLTParser.valueTemplate("id-{@n}-{{x}}")
        guard parts.count == 3 else {
            Issue.record("expected three parts, got \(parts.count)")
            return
        }
        if case let .literal(text) = parts[0] { #expect(text == "id-") } else { Issue.record("part 0") }
        if case let .expression(expr) = parts[1] { #expect(expr == "@n") } else { Issue.record("part 1") }
        if case let .literal(text) = parts[2] { #expect(text == "-{x}") } else { Issue.record("part 2") }
    }
}
