import Testing
@testable import PureXML

/// Per-entity base-URI tracking (#138): a relative system identifier inside
/// an external entity resolves against that entity's own URI, not the
/// document's, so nested external entities find their siblings (RFC 3986).
@Suite("Entity base URIs")
struct EntityBaseURITests {
    @Test("Nested relative identifiers resolve against the declaring entity's URI")
    func test_nestedRelativeResolution() throws {
        // The eduni E18 shape: subdir1/pe declares ../subdir2/extpe, which
        // declares the general entity the document references.
        let files: [String: String] = [
            "subdir1/pe": "<!ENTITY % extpe SYSTEM \"../subdir2/extpe\">\n<!ENTITY % intpe \"%extpe;\">",
            "subdir2/extpe": "<!ENTITY ent \"resolved\">",
        ]
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in files[id.systemID] },
            resolveExternalSubset: { id in files[id.systemID] },
        )
        let xml = """
        <!DOCTYPE foo [
        <!ELEMENT foo ANY>
        <!ENTITY % pe SYSTEM "subdir1/pe">
        %pe;
        %intpe;
        ]>
        <foo>&ent;</foo>
        """
        let node = try PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver)
        guard case let .document(children) = node, let foo = children.compactMap(\.element).first,
              case let .text(value)? = foo.children.first
        else {
            Issue.record("no text")
            return
        }
        #expect(value == "resolved")
    }

    @Test("The resolver still sees raw identifiers when no base applies")
    func test_documentLevelUnchanged() {
        let resolver = PureXML.Parsing.EntityResolver(
            resolveEntity: { _, id in id.systemID == "plain.ent" ? "ok" : nil },
            resolveExternalSubset: { _ in nil },
        )
        let xml = "<!DOCTYPE f [<!ELEMENT f ANY><!ENTITY e SYSTEM \"plain.ent\">]>\n<f>&e;</f>"
        #expect((try? PureXML.parse(xml, limits: .init(allowDoctype: true), resolver: resolver)) != nil)
    }
}
