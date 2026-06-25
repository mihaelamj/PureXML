import Testing
@testable import PureXML

/// `key()`, `id()`, and the EXSLT `set:leading`/`set:trailing` functions return
/// their nodes in document order. The order is now computed through the cached
/// `sortedByDocumentOrder`/`documentOrder(cache:)` path (not `sorted(by:precedes)`
/// or the cache-less key, which rescanned a wide parent per comparison), and
/// `key()` deduplicates through a set, not a linear membership scan. These pin
/// that the results are unchanged: the right nodes, in document order, once each.
@Suite("XSLT key/id/set document order and dedup")
struct XSLTKeyIdOrderTests {
    @Test("key() returns its matches in document order, deduplicated")
    func test_keyDedupAndOrder() throws {
        // Several values map to overlapping nodes; the node-set second argument
        // unions them and each matching node must appear once, in document order.
        let source = """
        <data>
          <r k="a">1</r><r k="b">2</r><r k="a">3</r><r k="c">4</r><r k="b">5</r>
          <want>a</want><want>b</want><want>a</want>
        </data>
        """
        let style = """
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="xml" indent="no"/>
          <xsl:key name="byK" match="r" use="@k"/>
          <xsl:template match="/">
            <out><xsl:for-each select="key('byK', /data/want)"><xsl:value-of select="."/>,</xsl:for-each></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let out = try PureXML.XSLT.transform(stylesheet: style, source: source)
        // k='a' -> nodes 1,3; k='b' -> nodes 2,5. Union, deduplicated, in
        // document order: 1,2,3,5.
        #expect(out.hasSuffix("<out>1,2,3,5,</out>"))
    }

    @Test("id() with several tokens returns the elements in document order")
    func test_idOrder() throws {
        let source = """
        <!DOCTYPE doc [<!ATTLIST item ref ID #IMPLIED>]>
        <doc><item ref="c">C</item><item ref="a">A</item><item ref="b">B</item></doc>
        """
        let style = """
        <xsl:stylesheet version="1.0" xmlns:xsl="http://www.w3.org/1999/XSL/Transform">
          <xsl:output method="xml" indent="no"/>
          <xsl:template match="/">
            <out><xsl:for-each select="id('b a c')"><xsl:value-of select="."/></xsl:for-each></out>
          </xsl:template>
        </xsl:stylesheet>
        """
        let out = try PureXML.XSLT.transform(stylesheet: style, source: source)
        // id() returns the referenced elements in document order regardless of the
        // token order: C, A, B as they appear.
        #expect(out.hasSuffix("<out>CAB</out>"))
    }
}
