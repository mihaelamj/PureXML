import Testing
@testable import PureXML

/// `evaluateSteps` skips cross-context node-set de-duplication on axes whose
/// results are disjoint per context (child, attribute, namespace, self) or when
/// there is a single context, and keeps it on the axes that can reach one node
/// from two contexts (ancestor, descendant, parent, the siblings,
/// following/preceding). These tests pin both directions: a shared node reached
/// from many contexts must appear exactly once, and a disjoint axis must still
/// return every distinct result.
@Suite("XPath node-set de-duplication")
struct XPathNodeSetDedupTests {
    /// Two subtrees, each holding a `c`, both under `root`; `a` holds two of them.
    private func doc() throws -> PureXML.Model.TreeNode {
        try PureXML.parseTree("<root><a><c/><c/></a><b><c/></b></root>")
    }

    private func count(_ path: String) throws -> Int {
        try Int(PureXML.XPath.Query("count(\(path))").value(at: doc()).number)
    }

    @Test("ancestor axis de-duplicates a node shared by many contexts")
    func test_ancestorDedup() throws {
        // Three `c` nodes all have `root` as an ancestor; it must be counted once.
        #expect(try count("//c/ancestor::root") == 1)
        // Two `c` nodes under `a` share `a` as parent; `a` counted once.
        #expect(try count("/root/a/c/parent::a") == 1)
        // descendant from multiple contexts: every `c` reached once.
        #expect(try count("/root/*/descendant-or-self::c") == 3)
    }

    @Test("disjoint axes return every distinct result")
    func test_disjointAxesComplete() throws {
        // child from multiple contexts: all three `c` children.
        #expect(try count("/root/*/child::c") == 3)
        // self from the three distinct `c` contexts: three nodes.
        #expect(try count("//c/self::c") == 3)
        // The whole node test still works under //.
        #expect(try count("//c") == 3)
    }

    @Test("a union of overlapping paths still de-duplicates")
    func test_unionDedup() throws {
        // `//c` and `//a//c` overlap on the two `c` under `a`; union is 3, not 5.
        #expect(try count("//c | //a//c") == 3)
    }
}
