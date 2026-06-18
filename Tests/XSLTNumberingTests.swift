import Testing
@testable import PureXML

/// The full `xsl:number` of XSLT 1.0 section 7.7 (#130): level
/// single/multiple/any with count and from patterns, the format-token engine
/// with punctuation and separators, digit grouping, and the value expression.
@Suite("XSLT numbering")
struct XSLTNumberingTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ number: String, source: String) throws -> String {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output omit-xml-declaration="yes"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//mark"/></out></xsl:template>
          <xsl:template match="mark">\(number)<xsl:text> </xsl:text></xsl:template>
        </xsl:stylesheet>
        """
        return try PureXML.XSLT.transform(stylesheet: style, source: source)
    }

    @Test("level=multiple numbers every matching ancestor-or-self, outermost first")
    func test_levelMultiple() throws {
        let source = """
        <doc><c><s><mark/></s><s><mark/><mark/></s></c><c><s><mark/></s></c></doc>
        """
        let result = try transform(
            "<xsl:number level=\"multiple\" count=\"c|s|mark\" format=\"1.1.\"/>",
            source: source,
        )
        #expect(result == "<out>1.1.1. 1.2.1. 1.2.2. 2.1.1. </out>")
    }

    @Test("level=any counts matching nodes before this one, bounded by from")
    func test_levelAny() throws {
        let source = "<doc><c><mark/><mark/></c><c><mark/></c></doc>"
        let across = try transform("<xsl:number level=\"any\" count=\"mark\"/>", source: source)
        #expect(across == "<out>1 2 3 </out>")
        let bounded = try transform("<xsl:number level=\"any\" count=\"mark\" from=\"c\"/>", source: source)
        #expect(bounded == "<out>1 2 1 </out>")
    }

    @Test("single/multiple with no matching node renders as the empty string")
    func test_emptyMatchIsEmptyOutput() throws {
        let result = try transform(
            "<xsl:number level=\"multiple\" count=\"missing\" format=\"1.1. \"/>",
            source: "<doc><mark/></doc>",
        )
        #expect(result == "<out> </out>")
    }

    @Test("format tokens: padding, alphabetic, roman, punctuation, last-token reuse")
    func test_formatTokens() {
        #expect(XSLTNumbering.format([3], "(001) ") == "(003) ")
        #expect(XSLTNumbering.format([2, 4], "A.i. ") == "B.iv. ")
        #expect(XSLTNumbering.format([1, 2, 3], "1-1. ") == "1-2-3. ")
        #expect(XSLTNumbering.format([1, 2, 3], "1") == "1.2.3")
        #expect(XSLTNumbering.format([], "(1) ").isEmpty)
    }

    @Test("digit grouping applies the separator from the right")
    func test_grouping() {
        #expect(XSLTNumbering.format([1234], "1", (separator: ",", size: 3)) == "1,234")
        #expect(XSLTNumbering.format([123], "1", (separator: ":", size: 2)) == "1:23")
        #expect(XSLTNumbering.format([12], "1", (separator: ",", size: 3)) == "12")
    }

    @Test("value= evaluates the expression; below one it bypasses formatting")
    func test_valueExpression() throws {
        let formatted = try transform("<xsl:number value=\"7\" format=\"(I)\"/>", source: "<doc><mark/></doc>")
        #expect(formatted == "<out>(VII) </out>")
        let zero = try transform("<xsl:number value=\"0\" format=\"(I) \"/>", source: "<doc><mark/></doc>")
        #expect(zero == "<out>0 </out>")
    }

    @Test("A value beyond 2^53 renders as a plain number without trapping")
    func test_hugeValue() throws {
        let result = try transform(
            "<xsl:number value=\"99999999999999999999 * 99999999999999999999\"/>",
            source: "<doc><mark/></doc>",
        )
        #expect(result == "<out>1" + String(repeating: "0", count: 40) + " </out>")
    }
}
