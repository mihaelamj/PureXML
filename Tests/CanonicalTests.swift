import Testing
@testable import PureXML

@Suite("Canonical XML")
struct CanonicalTests {
    private func c14n(_ xml: String, _ options: PureXML.Canonical.Options = .inclusive) throws -> String {
        try PureXML.Canonical.canonicalize(PureXML.parse(xml), options: options)
    }

    @Test("Empty elements expand to start/end pairs")
    func test_emptyElement() throws {
        #expect(try c14n("<a><b/></a>") == "<a><b></b></a>")
    }

    @Test("Attributes are sorted by namespace URI then local name")
    func test_attributeOrdering() throws {
        #expect(try c14n("<e c=\"3\" a=\"1\" b=\"2\"/>") == "<e a=\"1\" b=\"2\" c=\"3\"></e>")
    }

    @Test("Text special characters are escaped, but not quotes")
    func test_textEscaping() throws {
        #expect(try c14n("<a>1 &lt; 2 &amp; 3 > 4</a>") == "<a>1 &lt; 2 &amp; 3 &gt; 4</a>")
    }

    @Test("Attribute values escape quotes and whitespace, not >")
    func test_attributeEscaping() throws {
        let xml = "<a v=\"x&quot;y&#9;z\"/>"
        #expect(try c14n(xml) == "<a v=\"x&quot;y&#x9;z\"></a>")
    }

    @Test("Comments are omitted by default and kept when requested")
    func test_comments() throws {
        #expect(try c14n("<a><!--note--><b/></a>") == "<a><b></b></a>")
        let withComments = PureXML.Canonical.Options(includeComments: true)
        #expect(try c14n("<a><!--note--><b/></a>", withComments) == "<a><!--note--><b></b></a>")
    }

    @Test("CDATA is rendered as escaped text")
    func test_cdata() throws {
        #expect(try c14n("<a><![CDATA[x<y]]></a>") == "<a>x&lt;y</a>")
    }

    @Test("Namespace declarations are rendered and sorted, default first")
    func test_namespaceOrdering() throws {
        let xml = "<e xmlns:b=\"urn:b\" xmlns=\"urn:d\" xmlns:a=\"urn:a\"/>"
        #expect(try c14n(xml) == "<e xmlns=\"urn:d\" xmlns:a=\"urn:a\" xmlns:b=\"urn:b\"></e>")
    }

    @Test("Inclusive C14N keeps a namespace declared but only used by a child")
    func test_inclusiveKeepsUnused() throws {
        let xml = "<r xmlns:x=\"urn:x\"><x:c/></r>"
        #expect(try c14n(xml) == "<r xmlns:x=\"urn:x\"><x:c></x:c></r>")
    }

    @Test("Exclusive C14N drops a namespace no element visibly uses")
    func test_exclusiveDropsUnused() throws {
        let xml = "<r xmlns:x=\"urn:x\"><c/></r>"
        #expect(try c14n(xml, .exclusive) == "<r><c></c></r>")
    }

    @Test("Exclusive C14N renders a namespace at the element that uses it")
    func test_exclusiveRendersAtUse() throws {
        let xml = "<r xmlns:x=\"urn:x\"><x:c/></r>"
        #expect(try c14n(xml, .exclusive) == "<r><x:c xmlns:x=\"urn:x\"></x:c></r>")
    }

    @Test("A redundant child redeclaration is not rendered twice")
    func test_noRedundantDeclaration() throws {
        let xml = "<r xmlns=\"urn:d\"><c xmlns=\"urn:d\"/></r>"
        #expect(try c14n(xml) == "<r xmlns=\"urn:d\"><c></c></r>")
    }
}
