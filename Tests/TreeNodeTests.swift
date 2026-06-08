@testable import PureXML
import Testing

@Suite("Mutable tree")
struct TreeNodeTests {
    private typealias Tree = PureXML.Model.TreeNode

    // MARK: Navigation

    @Test("Parent and sibling links are wired from a parsed tree")
    func test_navigation() throws {
        let tree = try PureXML.parseTree("<r><a/><b/><c/></r>")
        let root = tree.firstChild
        let children = root?.children ?? []
        #expect(children.count == 3)
        #expect(children[1].parent === root)
        #expect(children[0].nextSibling === children[1])
        #expect(children[2].previousSibling === children[1])
        #expect(children[0].previousSibling == nil)
        #expect(children[2].nextSibling == nil)
    }

    @Test("Ancestors and root walk upward")
    func test_ancestors() throws {
        let tree = try PureXML.parseTree("<r><a><b/></a></r>")
        let deep = tree.firstChild?.firstChild?.firstChild
        #expect(deep?.name?.localName == "b")
        #expect(deep?.ancestors.map { $0.name?.localName ?? "#" } == ["a", "r", "#"])
        #expect(deep?.root === tree)
    }

    @Test("stringValue concatenates descendant text and CDATA")
    func test_stringValue() throws {
        let tree = try PureXML.parseTree("<r>a<x>b</x><![CDATA[c]]></r>")
        #expect(tree.firstChild?.stringValue == "abc")
    }

    @Test("elementChildren skips non-element nodes")
    func test_elementChildren() throws {
        let tree = try PureXML.parseTree("<r>text<a/><!--c--><b/></r>")
        #expect(tree.firstChild?.elementChildren.map { $0.name?.localName } == ["a", "b"])
    }

    // MARK: Mutation

    @Test("append moves a node and updates its parent")
    func test_append() {
        let root = Tree.element("r")
        let child = Tree.element("a")
        root.append(child)
        #expect(child.parent === root)
        #expect(root.children.count == 1)
    }

    @Test("Attaching a node detaches it from its previous parent")
    func test_reparenting() {
        let first = Tree.element("first")
        let second = Tree.element("second")
        let child = Tree.text("x")
        first.append(child)
        second.append(child)
        #expect(first.children.isEmpty)
        #expect(second.children.count == 1)
        #expect(child.parent === second)
    }

    @Test("insert before and after place a node correctly")
    func test_insertRelative() {
        let root = Tree.element("r")
        let first = Tree.element("a")
        let last = Tree.element("c")
        root.append(first)
        root.append(last)
        root.insert(Tree.element("b"), after: first)
        root.insert(Tree.element("start"), before: first)
        #expect(root.children.map { $0.name?.localName } == ["start", "a", "b", "c"])
    }

    @Test("removeFromParent detaches a node")
    func test_remove() {
        let root = Tree.element("r")
        let child = Tree.element("a")
        root.append(child)
        child.removeFromParent()
        #expect(root.children.isEmpty)
        #expect(child.parent == nil)
    }

    @Test("replace swaps a node in place")
    func test_replace() {
        let root = Tree.element("r")
        let old = Tree.element("old")
        root.append(old)
        old.replace(with: Tree.element("new"))
        #expect(root.children.map { $0.name?.localName } == ["new"])
        #expect(old.parent == nil)
    }

    @Test("copy is a deep clone sharing no nodes")
    func test_copy() {
        let root = Tree.element("r", children: [Tree.element("a", children: [Tree.text("x")])])
        let clone = root.copy()
        clone.firstChild?.firstChild?.value = "y"
        #expect(root.firstChild?.firstChild?.value == "x")
        #expect(clone.parent == nil)
        #expect(clone.firstChild !== root.firstChild)
    }

    @Test("A node cannot be made its own descendant")
    func test_noCycles() {
        let parent = Tree.element("p")
        let child = Tree.element("c")
        parent.append(child)
        child.append(parent)
        #expect(child.children.isEmpty)
        #expect(parent.children.count == 1)
    }

    // MARK: Round-trip

    @Test("A parsed tree round-trips back to identical XML")
    func test_roundTrip() throws {
        let xml = "<r a=\"1\"><b>text</b><c/></r>"
        let tree = try PureXML.parseTree(xml)
        #expect(PureXML.serialize(tree.node, options: .compact) == xml)
    }

    @Test("Edits show up in the serialized output")
    func test_editThenSerialize() throws {
        let tree = try PureXML.parseTree("<r><a/></r>")
        tree.firstChild?.append(Tree.element("b"))
        #expect(PureXML.serialize(tree.node, options: .compact) == "<r><a/><b/></r>")
    }
}
