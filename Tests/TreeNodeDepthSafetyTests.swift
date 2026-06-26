import Testing
@testable import PureXML

/// Depth safety for the mutable ``TreeNode`` tree type (#341): building a tree
/// from a value ``Node``, projecting it back, and releasing it must all run in
/// bounded native stack, so a deeply-nested document cannot overflow the call
/// stack through a recursive walk or a recursive chain of child releases.
///
/// The release test builds its tree bottom-up through the adopting initializer
/// rather than from a parsed value ``Node``: a value `Node` that deep still
/// releases recursively (its storage change is tracked separately in #341), so
/// using one as a fixture would itself overflow on teardown and mask what is
/// under test here.
@Suite("TreeNode depth safety")
struct TreeNodeDepthSafetyTests {
    /// A chain of `depth` nested elements, built bottom-up so construction never
    /// recurses and holds no deep value `Node`.
    private func deepChain(_ depth: Int) -> PureXML.Model.TreeNode {
        var node = PureXML.Model.TreeNode(adopting: .element, name: PureXML.Model.QualifiedName("a"), children: [])
        for _ in 0 ..< depth {
            node = PureXML.Model.TreeNode(adopting: .element, name: PureXML.Model.QualifiedName("a"), children: [node])
        }
        return node
    }

    @Test("releasing a 60k-deep tree does not overflow the stack")
    func test_deepReleaseIsBounded() {
        var root: PureXML.Model.TreeNode? = deepChain(60000)
        root = nil
        #expect(root == nil)
    }

    @Test("a held attached child keeps its subtree when the root is released")
    func test_heldChildKeepsSubtreeOnRootRelease() {
        let leaf = PureXML.Model.TreeNode.element("leaf")
        let mid = PureXML.Model.TreeNode.element("mid", children: [leaf])
        var root: PureXML.Model.TreeNode? = PureXML.Model.TreeNode.element("root", children: [mid])
        root = nil
        // The teardown only flattens nodes it solely owns; `mid` is still held, so
        // its subtree must remain intact rather than be cleared.
        #expect(mid.children.count == 1)
        #expect(mid.children.first === leaf)
        #expect(leaf.name?.description == "leaf")
    }

    @Test("Node to TreeNode and back round-trips through the iterative conversions")
    func test_conversionRoundTrip() throws {
        // Held at the default depth bound: a value `Node` this deep still releases
        // recursively, and a Swift Task's stack (this test runs on one) overflows
        // far shallower than the main thread, so a deeper fixture would crash on
        // teardown for a reason unrelated to the conversions under test (#341).
        let depth = 200
        let xml = String(repeating: "<a x=\"1\">", count: depth) + "leaf" + String(repeating: "</a>", count: depth)
        let node = try PureXML.parse(xml)
        let tree = PureXML.Model.TreeNode(node)
        let back = tree.node
        #expect(PureXML.serialize(back, options: .compact) == PureXML.serialize(node, options: .compact))
    }
}
