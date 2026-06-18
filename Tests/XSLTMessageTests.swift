import Testing
@testable import PureXML

@Suite("XSLT xsl:message")
struct XSLTMessageTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    @Test("A non-terminating message produces no output and does not abort")
    func test_nonTerminating() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/">
            <xsl:message>just a note</xsl:message>
            <out/>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(style, "<x/>") == "<out/>")
    }

    @Test("terminate=yes aborts the transform, carrying the message text")
    func test_terminate() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="/">
            <out/>
            <xsl:message terminate="yes">stop now</xsl:message>
          </xsl:template>
        </xsl:stylesheet>
        """
        var thrown: PureXML.XSLT.XSLTError?
        do {
            _ = try transform(style, "<x/>")
        } catch let error as PureXML.XSLT.XSLTError {
            thrown = error
        }
        #expect(thrown == .terminated("stop now"))
    }

    @Test("A terminating message can interpolate the source via value-of")
    func test_terminateDynamic() throws {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:template match="/">
            <xsl:message terminate="yes">bad value: <xsl:value-of select="r/@v"/></xsl:message>
          </xsl:template>
        </xsl:stylesheet>
        """
        #expect(throws: PureXML.XSLT.XSLTError.terminated("bad value: 7")) {
            _ = try transform(style, "<r v=\"7\"/>")
        }
    }
}
