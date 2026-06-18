import Testing
@testable import PureXML

@Suite("XSLT xsl:decimal-format")
struct XSLTDecimalFormatTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func formatNumber(_ select: String, decimalFormats: String = "") -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          \(decimalFormats)
          <xsl:template match="/"><xsl:value-of select="\(select)"/></xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("The default format still works")
    func test_default() throws {
        #expect(try transform(formatNumber("format-number(1234.5, '#,##0.00')"), "<x/>") == "1,234.50")
    }

    @Test("A named European format swaps the decimal and grouping separators")
    func test_european() throws {
        let style = formatNumber(
            "format-number(1234.5, '#.##0,00', 'eu')",
            decimalFormats: "<xsl:decimal-format name=\"eu\" decimal-separator=\",\" grouping-separator=\".\"/>",
        )
        #expect(try transform(style, "<x/>") == "1.234,50")
    }

    @Test("A custom percent and minus sign are honored")
    func test_percentMinus() throws {
        let style = formatNumber(
            "format-number(-0.25, '0%', 'p')",
            decimalFormats: "<xsl:decimal-format name=\"p\" minus-sign=\"!\"/>",
        )
        #expect(try transform(style, "<x/>") == "!25%")
    }

    @Test("A custom NaN string is used for non-numbers")
    func test_nan() throws {
        let style = formatNumber(
            "format-number(number('abc'), '0', 'n')",
            decimalFormats: "<xsl:decimal-format name=\"n\" NaN=\"not-a-number\"/>",
        )
        #expect(try transform(style, "<x/>") == "not-a-number")
    }

    @Test("The unnamed decimal-format overrides the global default")
    func test_unnamedDefault() throws {
        let style = formatNumber(
            "format-number(5, '0')",
            decimalFormats: "<xsl:decimal-format zero-digit=\"0\" minus-sign=\"~\"/>",
        )
        // 5 formats plainly; a negative shows the overridden minus sign.
        #expect(try transform(style, "<x/>") == "5")
        let neg = formatNumber("format-number(-5, '0')", decimalFormats: "<xsl:decimal-format minus-sign=\"~\"/>")
        #expect(try transform(neg, "<x/>") == "~5")
    }

    @Test("Literal affixes pass through around the number part")
    func test_affixes() throws {
        #expect(try transform(formatNumber("format-number(95.4857, 'PRE###.####SUF')"), "<x/>") == "PRE95.4857SUF")
        #expect(try transform(formatNumber("format-number(26931.4, '+#,###.#')"), "<x/>") == "+26,931.4")
    }

    @Test("The negative subpattern supplies its affixes; without distinguishing ones the minus sign applies")
    func test_negativeSubpattern() throws {
        #expect(try transform(formatNumber("format-number(-26931.4, '#,###.#;(#,###.#)')"), "<x/>") == "(26,931.4)")
        #expect(try transform(formatNumber("format-number(-26931.4, '#,###.#;#,###.#')"), "<x/>") == "-26,931.4")
        #expect(try transform(formatNumber("format-number(-87504.4812, '000,000.000###')"), "<x/>") == "-087,504.4812")
    }

    @Test("Per-mille multiplies by a thousand and keeps the symbol")
    func test_perMille() throws {
        #expect(try transform(formatNumber("format-number(0.4857, '###.###\u{2030}')"), "<x/>") == "485.7\u{2030}")
    }

    @Test("The grouping size comes from the pattern's last grouping separator")
    func test_groupingSize() throws {
        #expect(try transform(formatNumber("format-number(987654321, '###,##0,00.00')"), "<x/>") == "9,87,65,43,21.00")
    }

    @Test("Fraction digits render exactly, without float drift")
    func test_fractionExact() throws {
        #expect(try transform(formatNumber("format-number(87504.4812, '000,000.000###')"), "<x/>") == "087,504.4812")
    }

    @Test("Values beyond 2^53 format without trapping, digits exact")
    func test_hugeValues() throws {
        let huge = "99999999999999999999 * 99999999999999999999"
        #expect(try transform(formatNumber("format-number(\(huge), '0')"), "<x/>")
            == "1" + String(repeating: "0", count: 40))
        #expect(try transform(formatNumber("format-number(\(huge), '#,##0')"), "<x/>")
            == "10," + Array(repeating: "000", count: 13).joined(separator: ","))
    }

    @Test("A fraction picture beyond Double precision clamps to 18 places and pads")
    func test_absurdFractionPicture() throws {
        let result = try transform(formatNumber("format-number(0.5, '0.0000000000000000000000000')"), "<x/>")
        #expect(result == "0.5" + String(repeating: "0", count: 24))
    }
}
