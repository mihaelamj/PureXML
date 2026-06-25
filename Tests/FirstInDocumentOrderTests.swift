import Testing
@testable import PureXML

/// `firstInDocumentOrder()` returns the document-order minimum of a node-set. A
/// zero- or one-node set needs no ordering at all, so it skips the order-key
/// computation, which would otherwise scan the node's siblings: that scan over a
/// wide fan-out is what made single-node string extraction (`string(@x)`,
/// `value-of`) quadratic in an XSLT transform. These pin the trivial fast path
/// and that the multi-node path still picks the true document-order first.
@Suite("firstInDocumentOrder single-node fast path")
struct FirstInDocumentOrderTests {
    private func elements(_ xml: String) throws -> [PureXML.Model.TreeNode] {
        let root = try PureXML.parseTree(xml)
        guard let top = root.children.first(where: { $0.kind == .element }) else { return [] }
        return top.children.filter { $0.kind == .element }
    }

    @Test("an empty set has no first node")
    func test_empty() {
        let nodes: [PureXML.XPath.Node] = []
        #expect(nodes.firstInDocumentOrder() == nil)
    }

    @Test("a single-node set returns that node without ordering")
    func test_single() throws {
        let kids = try elements("<r><a/></r>")
        #expect([PureXML.XPath.Node.tree(kids[0])].firstInDocumentOrder() == .tree(kids[0]))
    }

    @Test("string-value picks the document-order-first of a multi-node set")
    func test_multiDocumentFirst() throws {
        // A union deliberately formed out of document order; `string()` takes the
        // value of the document-first node, which `firstInDocumentOrder` selects,
        // so this exercises the multi-node path past the single-node fast path.
        let tree = try PureXML.parseTree("<r><a>first</a><b>second</b><c>third</c></r>")
        let value = try PureXML.XPath.Query("string(//c | //a | //b)").value(at: tree).string
        #expect(value == "first")
    }

    @Test("the string-value of a single-node path over a wide tree is correct")
    func test_wideStringValue() throws {
        // A wide flat fan-out is exactly where the old per-node sibling scan went
        // quadratic; the value must be correct (and now linear to obtain).
        var items = ""
        for index in 0 ..< 500 {
            items += "<item id=\"i\(index)\"/>"
        }
        let tree = try PureXML.parseTree("<catalog>\(items)</catalog>")
        let value = try PureXML.XPath.Query("string(/catalog/item[300]/@id)").value(at: tree).string
        #expect(value == "i299")
    }
}
