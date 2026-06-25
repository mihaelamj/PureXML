import Testing
@testable import PureXML

/// `//X` compiles to `descendant-or-self::node()/child::X` and is fused to
/// `descendant::X` for speed. The fusion is valid only for non-positional
/// predicates: `//X[1]` is the first `X` child of EACH parent, which is NOT the
/// same node-set as `descendant::X[1]` (the first `X` in document order). These
/// tests pin that the positional forms keep their per-parent meaning (unfused)
/// while the non-positional forms select correctly (fused).
@Suite("XPath // descendant fusion")
struct XPathDescendantFusionTests {
    /// Two `x` children under `a`, one under `b`; ids in document order 1,2,3.
    private static let source = #"<r><a><x id="1"/><x id="2"/></a><b><x id="3"/></b></r>"#

    private func count(_ path: String) throws -> Int {
        try Int(PureXML.XPath.Query("count(\(path))").value(at: PureXML.parseTree(Self.source)).number)
    }

    private func ids(_ path: String) throws -> [String] {
        try PureXML.XPath.Query(path).evaluate(over: PureXML.parse(Self.source)).compactMap {
            if case let .node(node) = $0 { return node.element?.attributes.first { $0.name.localName == "id" }?.value }
            return nil
        }
    }

    @Test("a positional predicate under // keeps its per-parent meaning")
    func test_positionalNotFused() throws {
        // First x child of EACH parent: x1 (under a) and x3 (under b), not just x1.
        #expect(try count("//x[1]") == 2)
        #expect(try ids("//x[1]") == ["1", "3"])
        // Last x child of each parent: x2 (under a) and x3 (under b).
        #expect(try ids("//x[last()]") == ["2", "3"])
        // position()=2 child of each parent: only a has a second x (x2).
        #expect(try ids("//x[position()=2]") == ["2"])
    }

    @Test("a non-positional predicate under // selects across the whole subtree")
    func test_nonPositionalFused() throws {
        #expect(try ids("//x[@id='2']") == ["2"])
        #expect(try count("//x") == 3)
        #expect(try ids("//x[@id='1' or @id='3']") == ["1", "3"])
    }

    @Test("// fusion composes with later steps and nested paths")
    func test_fusionWithTrailingSteps() throws {
        // //a/x is the x children of every a; a single a here, two x.
        #expect(try count("//a/x") == 2)
        // A nested positional predicate binds to its own context, not the outer.
        #expect(try count("//a[x[1]]") == 1)
    }
}
