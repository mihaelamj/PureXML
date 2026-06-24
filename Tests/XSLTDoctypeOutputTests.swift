import Testing
@testable import PureXML

@Suite("XSLT xsl:output doctype-public / doctype-system")
struct XSLTDoctypeOutputTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("doctype-system emits a SYSTEM doctype before the root")
    func test_systemOnly() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes" doctype-system="note.dtd"/>
          <xsl:template match="/"><note/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<!DOCTYPE note SYSTEM \"note.dtd\">\n<note/>")
    }

    @Test("the html method names the doctype HTML regardless of the document element")
    func test_publicAndSystem() throws {
        // XSLT 1.0 16.2: the html output method's doctype name is HTML, not the
        // document element name (here `root`), unlike the xml method (Apache
        // Xalan output40, output48, output60).
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="html" doctype-public="-//W3C//DTD HTML 4.01//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd"/>
          <xsl:template match="/"><root/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>")
        #expect(out.hasPrefix("<!DOCTYPE HTML PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\n"))
        #expect(out.contains("<root></root>"))
    }

    @Test("the xml method still uses the document element name for the doctype")
    func test_xmlMethodUsesElementName() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes" doctype-system="note.dtd"/>
          <xsl:template match="/"><note/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<!DOCTYPE note SYSTEM \"note.dtd\">\n<note/>")
    }

    @Test("Without doctype-system no doctype is emitted")
    func test_none() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/"><note/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<note/>")
    }
}
