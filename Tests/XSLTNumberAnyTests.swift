import Testing
@testable import PureXML

/// `xsl:number level="any"` numbers a node by the count of matching nodes that
/// precede it (in document order, ancestors included) plus one. The walk over
/// preceding nodes now visits each preceding sibling's subtree directly instead
/// of rescanning the child list per sibling. These pin that the numbering is
/// unchanged: sequential in document order across nesting, counting only the
/// nodes the `count` pattern matches.
@Suite("xsl:number level=any")
struct XSLTNumberAnyTests {
    private func numbers(_ source: String, count: String = "item") throws -> [String] {
        let style = """
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="xml" indent="no"/>
          <xsl:template match="/"><out><xsl:apply-templates select="//item"/></out></xsl:template>
          <xsl:template match="item"><n><xsl:number level="any" count="\(count)"/></n></xsl:template>
        </xsl:stylesheet>
        """
        let out = try PureXML.XSLT.transform(stylesheet: style, source: source)
        // Extract the digits between <n>...</n>.
        return out.components(separatedBy: "<n>").dropFirst().map { String($0.prefix(while: { $0 != "<" })) }
    }

    @Test("items are numbered sequentially in document order across nesting")
    func test_sequential() throws {
        let source = "<doc><item/><g><item/><item/></g><item/></doc>"
        #expect(try numbers(source) == ["1", "2", "3", "4"])
    }

    @Test("only nodes the count pattern matches are counted")
    func test_countPattern() throws {
        // <other/> elements are interleaved but not counted; items still 1..3.
        let source = "<doc><other/><item/><other/><g><other/><item/></g><item/></doc>"
        #expect(try numbers(source) == ["1", "2", "3"])
    }

    @Test("a single item is number one")
    func test_single() throws {
        #expect(try numbers("<doc><g><h><item/></h></g></doc>") == ["1"])
    }
}
