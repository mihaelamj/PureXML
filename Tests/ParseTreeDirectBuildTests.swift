import Testing
@testable import PureXML

/// `parseTree` now assembles the `TreeNode` tree directly from the event stream
/// (`Parser.buildTree`) instead of building the value `Node` tree and converting
/// it. These pin that the direct build is structurally identical to the old
/// path, `TreeNode(parse(xml))`, for every node kind, attribute set, nesting,
/// namespace, mixed-content, and entity shape, including the parent links, and
/// that it still throws on the same malformed inputs.
@Suite("parseTree direct-build equivalence")
struct ParseTreeDirectBuildTests {
    private static let documents = [
        #"<r/>"#,
        #"<r></r>"#,
        #"<r a="1" b="2"/>"#,
        #"<r xmlns:m="urn:m"><m:c m:x="1"/><c/></r>"#,
        #"<r>text</r>"#,
        #"<r>mixed <b>bold</b> and <i>italic</i> tail</r>"#,
        #"<r>a &amp; b &lt; c &#65; &#x42;</r>"#,
        #"<r><![CDATA[<raw> & stuff]]></r>"#,
        #"<r><!-- comment --><?pi data?><c/></r>"#,
        #"<?xml version="1.0"?><!-- pre --><r><deep><deeper><x>v</x></deeper></deep></r><!-- post -->"#,
        #"<r>   <a/>  <b/> \#n</r>"#,
        #"<doc><p>one</p><p>two</p><p>three</p></doc>"#,
    ]

    /// Recursively asserts two trees are structurally identical and that each
    /// child's parent points back to its container in both.
    private func assertSameTree(_ direct: PureXML.Model.TreeNode, _ converted: PureXML.Model.TreeNode) {
        #expect(direct.kind == converted.kind)
        #expect(direct.name == converted.name)
        #expect(direct.value == converted.value)
        #expect(direct.attributes == converted.attributes)
        #expect(direct.children.count == converted.children.count)
        for (directChild, convertedChild) in zip(direct.children, converted.children) {
            #expect(directChild.parent === direct)
            #expect(convertedChild.parent === converted)
            assertSameTree(directChild, convertedChild)
        }
    }

    @Test("the direct build matches the convert-from-Node build for every document")
    func test_structuralEquivalence() throws {
        for document in Self.documents {
            let direct = try PureXML.parseTree(document)
            let converted = try PureXML.Model.TreeNode(PureXML.parse(document))
            assertSameTree(direct, converted)
        }
    }

    @Test("the direct build rejects the same malformed inputs")
    func test_sameRejections() {
        for malformed in ["", "<r>", "</r>", "<!-- only a comment -->", "<a><b></a></b>", "<r></s>"] {
            let directThrew = (try? PureXML.parseTree(malformed)) == nil
            let oldThrew = (try? PureXML.Model.TreeNode(PureXML.parse(malformed))) == nil
            #expect(directThrew == oldThrew, "rejection mismatch for \(malformed.debugDescription)")
        }
    }

    @Test("a serialized round-trip through the direct tree is unchanged")
    func test_roundTrip() throws {
        let document = #"<r xmlns:m="urn:m"><m:c a="1">x &amp; y</m:c><d><![CDATA[z]]></d></r>"#
        let direct = try PureXML.parseTree(document)
        let converted = try PureXML.Model.TreeNode(PureXML.parse(document))
        #expect(PureXML.serialize(direct.node) == PureXML.serialize(converted.node))
    }
}
