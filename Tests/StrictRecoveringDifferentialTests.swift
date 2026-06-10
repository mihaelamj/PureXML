@testable import PureXML
import Testing

/// Locks the strict and recovering parse paths together: the recovery code
/// synthesizes events through machinery the strict path never exercises, so
/// every well-formed document must produce the identical tree under both modes
/// with no diagnostics. (#116: a recovery-synthesis bug is invisible to
/// strict-path tests without this differential.)
@Suite("Strict vs recovering parser differential")
struct StrictRecoveringDifferentialTests {
    /// Well-formed documents spanning the constructs both paths must agree on,
    /// including the conformance-corpus inputs (kept in sync by inclusion).
    private let corpus = [
        // The C14N conformance-corpus inputs.
        "<e b=\"2\" a=\"1\"></e>",
        "<e/>",
        "<e><!--c-->x</e>",
        "<e><![CDATA[<x>&]]></e>",
        "<e><?pi data?></e>",
        "<e xmlns=\"urn:x\"></e>",
        // Structure: nesting, siblings, mixed content, whitespace.
        "<r><a><b><c>deep</c></b></a></r>",
        "<r><i>1</i><i>2</i><i>3</i></r>",
        "<p>text <b>bold</b> tail</p>",
        "<r>\n  <a/>\n  <b/>\n</r>",
        // Attributes: quoting, escapes, namespaces on attributes.
        "<e a=\"x&amp;y\" b=\"&lt;tag&gt;\"/>",
        "<e a='single' b=\"double\"/>",
        "<r xmlns:p=\"urn:x\"><p:c p:attr=\"v\"/></r>",
        // Entities and character references.
        "<e>&amp;&lt;&gt;&quot;&apos;</e>",
        "<e>&#65;&#x42;</e>",
        // Prolog and misc constructs.
        "<?xml version=\"1.0\"?><r/>",
        "<!-- leading --><r/><!-- trailing -->",
        "<r><![CDATA[]]></r>",
        "<r xml:space=\"preserve\">  kept  </r>",
        // Default and redeclared namespaces.
        "<r xmlns=\"urn:a\"><c xmlns=\"urn:b\"><d/></c></r>",
    ]

    @Test("Well-formed documents parse identically in strict and recovering modes")
    func test_treesAgree() throws {
        for document in corpus {
            let strict = try PureXML.parse(document)
            let recovered = PureXML.read(document)
            #expect(recovered.diagnostics.isEmpty, "unexpected diagnostics for: \(document) -> \(recovered.diagnostics)")
            #expect(recovered.node == strict, "trees diverged for: \(document)")
        }
    }

    @Test("The recovering editor tree projects to the same node as strict parse")
    func test_readTreeAgrees() throws {
        for document in corpus {
            let strict = try PureXML.parse(document)
            let (tree, diagnostics) = PureXML.readTree(document)
            #expect(diagnostics.isEmpty, "unexpected diagnostics for: \(document)")
            #expect(tree.node == strict, "readTree diverged for: \(document)")
        }
    }
}
