@testable import PureXML
import Testing

@Suite("TreeNode editing: attributes, copy, order, normalize")
struct TreeNodeEditingTests {
    private typealias Tree = PureXML.Model.TreeNode

    @Test("Attribute get, set, and remove")
    func test_attributes() {
        let element = Tree.element("a", attributes: [PureXML.Model.Attribute("id", "1")])
        #expect(element.attributeValue("id") == "1")
        element.setAttribute("id", "2")
        #expect(element.attributeValue("id") == "2")
        element.setAttribute("class", "x")
        #expect(element.attributeValue("class") == "x")
        #expect(element.attributes.count == 2)
        let removed = element.removeAttribute("id")
        #expect(removed)
        #expect(element.attributeValue("id") == nil)
        let removedAgain = element.removeAttribute("id")
        #expect(!removedAgain)
    }

    @Test("setAttribute is a no-op on a non-element node")
    func test_setAttributeOnText() {
        let text = Tree.text("hi")
        text.setAttribute("id", "1")
        #expect(text.attributes.isEmpty)
    }

    @Test("shallowCopy copies the node without its children or parent")
    func test_shallowCopy() {
        let parent = Tree.element("a", children: [Tree.element("b")])
        let child = parent.children[0]
        child.setAttribute("k", "v")
        let copy = child.shallowCopy()
        #expect(copy.name?.localName == "b")
        #expect(copy.attributeValue("k") == "v")
        #expect(copy.children.isEmpty)
        #expect(copy.parent == nil)
    }

    @Test("Document order: ancestor precedes descendant and earlier siblings precede later")
    func test_documentOrder() {
        let root = Tree.element("a")
        let first = Tree.element("b")
        let second = Tree.element("c")
        root.append(first)
        root.append(second)
        let deep = Tree.element("d")
        first.append(deep)
        #expect(root.precedes(first)) // ancestor before descendant
        #expect(first.precedes(second)) // earlier sibling before later
        #expect(deep.precedes(second)) // deep node before its parent's later sibling
        #expect(!second.precedes(first))
        #expect(!root.precedes(root))
    }

    @Test("Document order across unrelated trees is false")
    func test_documentOrderUnrelated() {
        let one = Tree.element("x")
        let two = Tree.element("y")
        #expect(!one.precedes(two))
        #expect(!two.precedes(one))
    }

    @Test("normalize coalesces adjacent text and drops empty text")
    func test_normalize() {
        let element = Tree.element("a")
        element.append(Tree.text("foo"))
        element.append(Tree.text(""))
        element.append(Tree.text("bar"))
        element.append(Tree.comment("c"))
        element.append(Tree.text("baz"))
        element.normalize()
        #expect(element.children.count == 3) // "foobar", comment, "baz"
        #expect(element.children[0].kind == .text)
        #expect(element.children[0].value == "foobar")
        #expect(element.children[1].kind == .comment)
        #expect(element.children[2].value == "baz")
    }

    @Test("normalize does not merge CDATA with text and recurses into elements")
    func test_normalizeCDATAandRecursion() {
        let inner = Tree.element("b")
        inner.append(Tree.text("x"))
        inner.append(Tree.text("y"))
        let element = Tree.element("a")
        element.append(Tree.text("t"))
        element.append(Tree.cdata("data"))
        element.append(inner)
        element.normalize()
        #expect(element.children.count == 3) // text, cdata, element (all distinct)
        #expect(inner.children.count == 1)
        #expect(inner.children[0].value == "xy")
    }
}
