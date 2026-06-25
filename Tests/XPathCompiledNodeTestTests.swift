import Testing
@testable import PureXML

/// The compiled per-node tests (`compiledTreeTest`, `compiledAttributeTest`,
/// `compiledNodeTest`) hoist a step's invariant structure (the axis principal
/// kind, the binding state, the prefix-wildcard shape) out of the per-node path
/// so a wide traversal resolves it once, not on every node. They must stay
/// exactly equivalent to the unfused `matchesTree`, `matchesAttribute`, and
/// `matches` they specialize: a divergence would make a fused traversal select
/// different nodes than the filter fallback. This walks a document covering
/// every node kind and asserts equivalence across every test, axis, and
/// binding, so a future edit to a `matches*` function that forgets its compiled
/// twin fails here.
@Suite("XPath compiled node-test equivalence")
struct XPathCompiledNodeTestTests {
    private static let source =
        #"<r xmlns:k="urn:k"><e a="1" k:c="3">text<k:e b="2"/><!--c--><?pi go?></e><k:e/></r>"#

    private typealias Eval = PureXML.XPath.Evaluator
    private typealias Test = PureXML.XPath.NodeTest
    private typealias Axis = PureXML.XPath.Axis

    private static let tests: [Test] = [
        .name("e"), .name("k:e"), .name("k:c"), .name("k:*"), .name("missing"),
        .wildcard, .node, .text, .comment,
        .processingInstruction(target: nil), .processingInstruction(target: "pi"),
    ]
    private static let axes: [Axis] = [
        .child, .descendant, .descendantOrSelf, .attribute, .namespace,
        .selfAxis, .parent, .ancestor, .following, .preceding,
        .followingSibling, .precedingSibling, .ancestorOrSelf,
    ]
    private static let bindings: [[String: String]] = [[:], ["k": "urn:k"]]

    private func allTreeNodes(_ root: PureXML.Model.TreeNode) -> [PureXML.Model.TreeNode] {
        var out = [root]
        for child in root.children {
            out += allTreeNodes(child)
        }
        return out
    }

    @Test("compiledTreeTest equals matchesTree for every node, test, axis, binding")
    func test_treeEquivalence() throws {
        let nodes = try allTreeNodes(PureXML.parseTree(Self.source))
        for namespaces in Self.bindings {
            for axis in Self.axes {
                for test in Self.tests {
                    let compiled = Eval.compiledTreeTest(test, on: axis, namespaces)
                    for node in nodes {
                        #expect(
                            compiled(node) == Eval.matchesTree(node, test, on: axis, namespaces),
                            "tree test=\(test) axis=\(axis) ns=\(namespaces)",
                        )
                    }
                }
            }
        }
    }

    @Test("compiledNodeTest equals matches for tree, attribute, and namespace nodes")
    func test_nodeEquivalence() throws {
        let trees = try allTreeNodes(PureXML.parseTree(Self.source))
        var nodes: [PureXML.XPath.Node] = trees.map { .tree($0) }
        for tree in trees {
            for attr in tree.attributes {
                nodes.append(.attribute(owner: tree, attr))
            }
        }
        nodes.append(.namespace(owner: trees[0], prefix: "k", uri: "urn:k"))
        for namespaces in Self.bindings {
            for axis in Self.axes {
                for test in Self.tests {
                    let compiled = Eval.compiledNodeTest(test, on: axis, namespaces)
                    for node in nodes {
                        #expect(
                            compiled(node) == Eval.matches(node, test, on: axis, namespaces: namespaces),
                            "node test=\(test) axis=\(axis) ns=\(namespaces)",
                        )
                    }
                }
            }
        }
    }

    @Test("compiledAttributeTest equals matchesAttribute for every attribute, test, binding")
    func test_attributeEquivalence() throws {
        let attrs = try allTreeNodes(PureXML.parseTree(Self.source)).flatMap(\.attributes)
        for namespaces in Self.bindings {
            for test in Self.tests {
                let compiled = Eval.compiledAttributeTest(test, namespaces)
                for attr in attrs {
                    #expect(
                        compiled(attr) == Eval.matchesAttribute(attr, test, namespaces),
                        "attr test=\(test) ns=\(namespaces)",
                    )
                }
            }
        }
    }
}
