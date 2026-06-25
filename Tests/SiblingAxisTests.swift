import Testing
@testable import PureXML

/// The following-sibling and preceding-sibling axes look up a node's index among
/// its parent's children through a shared cache (not a scan per context node)
/// and fuse the step's node test into the walk (a rejected sibling is never
/// wrapped). These pin that the selected siblings and their order are unchanged:
/// a name test selects only matching siblings, and the path result is in
/// document order for both axes.
@Suite("following-sibling and preceding-sibling axes")
struct SiblingAxisTests {
    private static let doc = "<r><a/><b/><c/><a/><d/></r>"

    private func names(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.doc)).compactMap {
            if case let .node(node) = $0 { return node.element?.name.localName }
            return nil
        }
    }

    @Test("following-sibling selects later siblings in document order")
    func test_following() throws {
        #expect(try names("//b/following-sibling::*") == ["c", "a", "d"])
        // A name test keeps only the matching siblings (the fused node test).
        #expect(try names("//b/following-sibling::a") == ["a"])
        #expect(try names("//d/following-sibling::*") == [])
    }

    @Test("preceding-sibling selects earlier siblings (path result in document order)")
    func test_preceding() throws {
        #expect(try names("//c/preceding-sibling::*") == ["a", "b"])
        #expect(try names("//d/preceding-sibling::a") == ["a", "a"])
        #expect(try names("//a/preceding-sibling::*") == ["a", "b", "c"])
    }

    @Test("the axes are correct across many context nodes (shared cache)")
    func test_manyContexts() throws {
        let xml = "<r>" + String(repeating: "<x/>", count: 60) + "</r>"
        // Each x[i] has 60 - i following x siblings; the deduplicated union is the
        // 59 x's after the first.
        let total = try Int(PureXML.XPath.Query("count(//x/following-sibling::x)").value(at: PureXML.parseTree(xml)).number)
        #expect(total == 59)
    }
}
