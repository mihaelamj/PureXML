@testable import PureXML
import Testing

@Suite("XSLT functions: generate-id, system-property, *-available")
struct XSLTFunctionTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ stylesheet: String, _ source: String) throws -> String {
        try PureXML.XSLT.transform(stylesheet: stylesheet, source: source)
    }

    private func valueOf(_ select: String) -> String {
        """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="\(select)"/></xsl:template>
        </xsl:stylesheet>
        """
    }

    @Test("system-property reports the XSLT version and vendor")
    func test_systemProperty() throws {
        #expect(try transform(valueOf("system-property('xsl:version')"), "<x/>") == "1")
        #expect(try transform(valueOf("system-property('xsl:vendor')"), "<x/>") == "PureXML")
    }

    @Test("element-available is true for a supported instruction, false otherwise")
    func test_elementAvailable() throws {
        #expect(try transform(valueOf("element-available('xsl:if')"), "<x/>") == "true")
        #expect(try transform(valueOf("element-available('xsl:nonesuch')"), "<x/>") == "false")
    }

    @Test("function-available is true for known functions, false otherwise")
    func test_functionAvailable() throws {
        #expect(try transform(valueOf("function-available('concat')"), "<x/>") == "true")
        #expect(try transform(valueOf("function-available('generate-id')"), "<x/>") == "true")
        #expect(try transform(valueOf("function-available('made-up')"), "<x/>") == "false")
    }

    @Test("generate-id is stable per node and differs between nodes")
    func test_generateId() throws {
        // Same node twice is equal; two different nodes are not.
        let same = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="generate-id(r/a) = generate-id(r/a)"/></xsl:template>
        </xsl:stylesheet>
        """
        let differ = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="text"/>
          <xsl:template match="/"><xsl:value-of select="generate-id(r/a) = generate-id(r/b)"/></xsl:template>
        </xsl:stylesheet>
        """
        #expect(try transform(same, "<r><a/><b/></r>") == "true")
        #expect(try transform(differ, "<r><a/><b/></r>") == "false")
    }

    @Test("generate-id produces an XML-name-shaped id")
    func test_generateIdShape() throws {
        let out = try transform(valueOf("generate-id(.)"), "<x/>")
        #expect(out.hasPrefix("N"))
        #expect(out.count > 1)
    }
}
