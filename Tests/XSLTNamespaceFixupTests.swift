import Testing
@testable import PureXML

/// Result-tree namespace fixup (XSLT 1.0 section 7.1). A namespaced attribute
/// with no usable in-scope prefix gets a generated `ns<n>` prefix and a matching
/// `xmlns:ns<n>` declaration; an unqualified element reached under an inherited
/// default namespace undeclares that default with `xmlns=""`. These run on every
/// transform result (`XSLTNamespaceFixup.apply`, called from the serializer) but
/// were previously only exercised on the prefix-already-present path.
@Suite("XSLT result-tree namespace fixup")
struct XSLTNamespaceFixupTests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    private func transform(_ template: String) throws -> String {
        let style = """
        <xsl:stylesheet version="1.0" \(xsl)>
          <xsl:output method="xml" omit-xml-declaration="yes"/>
          <xsl:template match="/">\(template)</xsl:template>
        </xsl:stylesheet>
        """
        return try PureXML.XSLT.transform(stylesheet: style, source: "<x/>")
    }

    @Test("a namespaced attribute with no carried prefix gets a generated ns0 prefix")
    func test_attributePrefixGenerated() throws {
        #expect(try transform(#"<out><xsl:attribute name="foo" namespace="urn:x">v</xsl:attribute></out>"#)
            == #"<out ns0:foo="v" xmlns:ns0="urn:x"/>"#)
    }

    @Test("two attributes in distinct namespaces take ns0 then ns1")
    func test_twoAttributePrefixesIncrement() throws {
        #expect(try transform(#"<out><xsl:attribute name="a" namespace="urn:one">1</xsl:attribute><xsl:attribute name="b" namespace="urn:two">2</xsl:attribute></out>"#)
            == #"<out ns0:a="1" ns1:b="2" xmlns:ns0="urn:one" xmlns:ns1="urn:two"/>"#)
    }

    @Test("an unqualified element under an inherited default namespace undeclares it")
    func test_undeclareInheritedDefault() throws {
        #expect(try transform(#"<out xmlns="urn:d"><xsl:element name="plain" namespace=""/></out>"#)
            == #"<out xmlns="urn:d"><plain xmlns=""/></out>"#)
    }
}
