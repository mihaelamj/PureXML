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
}
