import Testing
@testable import PureXML

/// The following and preceding axes now share a per-query cache of the document
/// node list and a node-to-index map (instead of rebuilding and linearly
/// searching the whole document on every context node), and `following::` skips
/// the context's contiguous subtree by index arithmetic rather than filtering
/// every descendant out. These pin that the selected nodes and their order are
/// unchanged across nesting (where the subtree skip must count every descendant)
/// and multiple context nodes (where the cache is shared).
@Suite("following and preceding axes")
struct FollowingPrecedingAxisTests {
    private func names(_ path: String, _ xml: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(xml)).compactMap {
            if case let .node(node) = $0 { return node.element?.name.localName }
            return nil
        }
    }

    private static let doc = "<r><a><a1/><a2/></a><b><b1><b11/></b1></b><c/><a><a3/></a></r>"

    @Test("following:: skips the context's whole subtree, in document order")
    func test_following() throws {
        // From <b>, following is c and the second <a> and its child a3 (NOT b's
        // own descendants b1/b11). The subtree-skip by index must count b1 and
        // b11 so it lands past them.
        #expect(try names("//b/following::*", Self.doc) == ["c", "a", "a3"])
        // From a deeply nested node, following is everything after its subtree.
        #expect(try names("//a1/following::*", Self.doc) == ["a2", "b", "b1", "b11", "c", "a", "a3"])
        // following of a node with no following nodes is empty.
        #expect(try names("//a3/following::*", Self.doc) == [])
    }

    @Test("preceding:: excludes ancestors")
    func test_preceding() throws {
        // The path result is a deduplicated node-set returned in document order.
        // From <c>, preceding is everything before it except its ancestors (only
        // r), so a, a1, a2, b, b1, b11.
        #expect(try names("//c/preceding::*", Self.doc) == ["a", "a1", "a2", "b", "b1", "b11"])
        // From b11, preceding excludes its ancestors b, b1 (and r), leaving the
        // first <a> subtree.
        #expect(try names("//b11/preceding::*", Self.doc) == ["a", "a1", "a2"])
    }

    @Test("a name test fused into the walk selects only matching nodes")
    func test_fusedNodeTest() throws {
        // following::a from a1 selects only the later <a> (the one holding a3),
        // not a2/b/b1/b11/c; preceding::a from c selects only the first <a>.
        #expect(try names("//a1/following::a", Self.doc) == ["a"])
        #expect(try names("//c/preceding::a", Self.doc) == ["a"])
        #expect(try names("//a1/following::b11", Self.doc) == ["b11"])
        #expect(try names("//a3/preceding::a1", Self.doc) == ["a1"])
    }

    @Test("the axes give the same result from many context nodes (shared cache)")
    func test_manyContexts() throws {
        // Exercises the shared per-query cache across context nodes. The path is a
        // deduplicated node-set: every x except the first appears in some node's
        // following set, so the union is the 49 later x elements.
        let xml = "<r>" + String(repeating: "<x/>", count: 50) + "</r>"
        let total = try Int(PureXML.XPath.Query("count(//x/following::x)").value(at: PureXML.parseTree(xml)).number)
        #expect(total == 49)
    }
}
