import Testing
@testable import PureXML

@Suite("Canonical XML: node-set (position-based) selection")
struct CanonicalSelectionTests {
    private func select(
        _ xml: String,
        _ options: PureXML.Canonical.Options = .inclusive,
        where predicate: @escaping (PureXML.Model.TreeNode) -> Bool,
    ) throws -> String {
        let document = try PureXML.parseTree(xml)
        return PureXML.Canonical.Canonicalizer(options: options).canonicalize(document, including: predicate)
    }

    @Test("An excluded element and its subtree are dropped")
    func test_excludeSubtree() throws {
        let output = try select("<r><a/><b/></r>") { $0.name?.localName != "b" }
        #expect(output == "<r><a></a></r>")
    }

    @Test("An excluded middle element is omitted but its selected child is kept")
    func test_omitMiddleKeepChild() throws {
        let output = try select("<r><skip><keep/></skip></r>") { $0.name?.localName != "skip" }
        #expect(output == "<r><keep></keep></r>")
    }

    @Test("A selected node exposed by omitted ancestors re-declares its namespace context")
    func test_exposedReDeclaresNamespace() throws {
        let output = try select("<r xmlns:p=\"urn:x\"><skip><p:keep/></skip></r>") { $0.name?.localName == "keep" }
        #expect(output == "<p:keep xmlns:p=\"urn:x\"></p:keep>")
    }

    @Test("Selecting every node reproduces the ordinary canonical form")
    func test_selectAllMatchesWholeTree() throws {
        let xml = "<r xmlns:p=\"urn:x\"><p:c>hi</p:c></r>"
        let selected = try select(xml) { _ in true }
        let whole = try PureXML.Canonical.canonicalize(PureXML.parse(xml))
        #expect(selected == whole)
        #expect(selected == "<r xmlns:p=\"urn:x\"><p:c>hi</p:c></r>")
    }
}
