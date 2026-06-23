import Testing
@testable import PureXML

/// `document()` resolves a relative URI reference against a base URI (XSLT 1.0
/// 12.1): the second argument's first node supplies the base for the two-argument
/// form, and a node's own document supplies it for the node-set form. A document
/// loaded from `dir/sub/inner.xml` lends its `dir/sub/` directory to references
/// taken relative to it.
@Suite("XSLT document() base URI")
struct XSLTDocumentBaseURITests {
    private let xsl = "xmlns:xsl=\"http://www.w3.org/1999/XSL/Transform\""

    /// A loader over a fixed in-memory directory tree, exact path to content.
    private static let files = [
        "dir/sub/inner.xml": "<inner><ref>sibling.xml</ref></inner>",
        "dir/sub/target.xml": "<hit>TWO_ARG</hit>",
        "dir/sub/sibling.xml": "<sib>NODE_SET</sib>",
    ]

    private func run(_ select: String) throws -> String {
        try PureXML.XSLT.transform(
            stylesheet: """
            <xsl:stylesheet version="1.0" \(xsl)>
              <xsl:output omit-xml-declaration="yes"/>
              <xsl:template match="/"><out><xsl:value-of select="\(select)"/></out></xsl:template>
            </xsl:stylesheet>
            """,
            source: "<doc/>",
            documentLoader: { Self.files[$0] },
        )
    }

    @Test("two-argument form resolves against the second argument's base URI")
    func test_twoArgument() throws {
        // `target.xml` resolves against `dir/sub/inner.xml`, reaching dir/sub/target.xml.
        let out = try run("document('target.xml', document('dir/sub/inner.xml'))/hit")
        #expect(out == "<out>TWO_ARG</out>")
    }

    @Test("node-set form resolves against the referencing node's own base URI")
    func test_nodeSet() throws {
        // The <ref> node lives in dir/sub/inner.xml, so its `sibling.xml` value
        // resolves to dir/sub/sibling.xml.
        let out = try run("document(document('dir/sub/inner.xml')/inner/ref)/sib")
        #expect(out == "<out>NODE_SET</out>")
    }

    @Test("a fragment-selected node still carries its document's base URI")
    func test_fragmentBase() throws {
        // The fragment selection is a detached subtree, yet it must still resolve
        // `target.xml` against dir/sub/inner.xml's directory.
        let out = try run("document('target.xml', document('dir/sub/inner.xml#xpointer(/inner)'))/hit")
        #expect(out == "<out>TWO_ARG</out>")
    }

    /// A string-form `document()` reference resolves against the base URI of the
    /// stylesheet element holding it, which for a declaration in an included or
    /// imported file is that file's URI, not the top stylesheet's (XSLT 1.0 12.1;
    /// the semantics behind Apache Xalan impincl08).
    @Test("a global document() in an included file resolves against the included file's base")
    func test_includedGlobalBase() throws {
        let files = [
            "lib/inc.xsl": """
            <xsl:stylesheet version="1.0" \(xsl)>
              <xsl:variable name="d" select="document('data.xml')"/>
              <xsl:template name="emit"><xsl:value-of select="$d/d/v"/></xsl:template>
            </xsl:stylesheet>
            """,
            "lib/data.xml": "<d><v>INCLUDED</v></d>",
        ]
        let out = try PureXML.XSLT.transform(
            stylesheet: """
            <xsl:stylesheet version="1.0" \(xsl)>
              <xsl:output omit-xml-declaration="yes"/>
              <xsl:include href="lib/inc.xsl"/>
              <xsl:template match="/"><out><xsl:call-template name="emit"/></out></xsl:template>
            </xsl:stylesheet>
            """,
            source: "<doc/>",
            documentLoader: { files[$0] },
        )
        // `data.xml` resolves against lib/inc.xsl, reaching lib/data.xml; without
        // base provenance it would resolve against the top stylesheet and miss.
        #expect(out == "<out>INCLUDED</out>")
    }
}
