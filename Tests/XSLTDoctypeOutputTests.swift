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

    @Test("doctype-public and doctype-system emit a PUBLIC doctype")
    func test_publicAndSystem() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="html" doctype-public="-//W3C//DTD HTML 4.01//EN" doctype-system="http://www.w3.org/TR/html4/strict.dtd"/>
          <xsl:template match="/"><html/></xsl:template>
        </xsl:stylesheet>
        """
        let out = try transform(style, "<x/>")
        #expect(out.hasPrefix("<!DOCTYPE html PUBLIC \"-//W3C//DTD HTML 4.01//EN\" \"http://www.w3.org/TR/html4/strict.dtd\">\n"))
        #expect(out.contains("<html></html>"))
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
