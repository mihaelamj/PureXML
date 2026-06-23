import Testing
@testable import PureXML

/// Top-level variables and parameters may reference one another in any document
/// order (XSLT 1.0 section 11.4), so the engine resolves them to a fixpoint
/// rather than once top-to-bottom (Apache Xalan variable33-35).
@Suite("XSLT global variable evaluation order")
struct XSLTGlobalVariableTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    @Test("A global variable resolves a forward reference to a later global")
    func test_forwardReference() throws {
        // `b` is declared before `a` but references it; both must resolve.
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:variable name="b" select="$a"/>
          <xsl:variable name="a" select="/doc/v"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="$b"/></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<doc><v>GotIt</v></doc>") == "<out>GotIt</out>")
    }

    @Test("A cascaded chain of globals declared in reverse order all resolve")
    func test_cascadedReverseOrder() throws {
        // b<-a, e<-d, a<-source, d<-c, c<-b: a deep forward-reference chain
        // that only settles when evaluated to a fixpoint, not in document order.
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:variable name="b" select="$a"/>
          <xsl:variable name="e" select="$d"/>
          <xsl:variable name="a" select="/doc/v"/>
          <xsl:variable name="d" select="$c"/>
          <xsl:variable name="c" select="$b"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="$e"/></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<doc><v>GotIt</v></doc>") == "<out>GotIt</out>")
    }

    @Test("A variable is named by expanded QName: prefixes sharing a namespace name the same variable")
    func test_variableMatchedByExpandedName() throws {
        // txt and new are both bound to urn:v, so $new:x references the variable
        // declared as txt:x (XSLT 1.0 11.1, Apache Xalan variable55).
        let style = """
        <xsl:stylesheet version="1.0" \(xsl) xmlns:txt="urn:v" xmlns:new="urn:v" exclude-result-prefixes="txt new">
          <xsl:variable name="txt:x" select="'Wizard'"/>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:value-of select="$new:x"/></out></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try PureXML.XSLT.transform(stylesheet: style, source: "<x/>") == "<out>Wizard</out>")
    }
}
