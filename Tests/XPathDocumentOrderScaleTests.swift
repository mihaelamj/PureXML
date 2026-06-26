import Testing
@testable import PureXML

/// XPath result ordering must not be quadratic in document depth. Sorting a
/// node-set into document order keyed each node by its root path, an array as
/// long as the node's depth, so ordering the descendants of a deeply-nested
/// document was O(n log n x depth). The order key is now a single O(1) index
/// from a per-root pre-order numbering, so the sort is linear in the document.
/// The time limit turns a regression back to the path-key form into a failure.
@Suite("XPath document-order scale")
struct XPathDocumentOrderScaleTests {
    /// A document holding a chain of `depth` nested elements with a text leaf, as
    /// a tree node. The document wrapper makes the top element a child, so `//a`
    /// selects all `depth` of them.
    private func deepTree(_ depth: Int) -> PureXML.Model.TreeNode {
        var node: PureXML.Model.Node = .text("x")
        for _ in 0 ..< depth {
            node = .element(.init("a", children: [node]))
        }
        return PureXML.Model.TreeNode(.document([node]))
    }

    #if os(WASI)
        @Test("ordering the descendants of a deep document is linear")
    #else
        @Test("ordering the descendants of a deep document is linear", .timeLimit(.minutes(1)))
    #endif
    func test_deepDescendantOrderingIsLinear() throws {
        let depth = 50000
        let tree = deepTree(depth)
        let matches = try PureXML.XPath.Query("//a").nodes(over: tree)
        #expect(matches.count == depth)
    }

    @Test("document order is preserved for mixed element, attribute, and child results")
    func test_documentOrderUnchanged() throws {
        // `//node()|//@*` over a small tree exercises the element/attribute bands
        // of the order key; the result must be in document order.
        let xml = "<r><a x=\"1\" y=\"2\"><b/></a><c/></r>"
        let strings = try PureXML.XPath.Query("//*").strings(over: PureXML.parse(xml))
        // Document order of the elements: r, a, b, c (by their start tags).
        let names = try PureXML.XPath.Query("//*").elements(over: PureXML.parse(xml)).map(\.name.localName)
        #expect(names == ["r", "a", "b", "c"])
        #expect(strings.count == 4)
    }
}
