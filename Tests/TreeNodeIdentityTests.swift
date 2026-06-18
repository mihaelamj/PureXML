import Testing
@testable import PureXML

@Suite("TreeNode DOM identity: structural kinds, ownerDocument, adoption")
struct TreeNodeIdentityTests {
    private typealias Tree = PureXML.Model.TreeNode

    @Test("Doctype node carries name, identifiers, and internal subset")
    func test_doctype() {
        let doctype = Tree.doctype(
            name: "html",
            publicID: "-//W3C//DTD XHTML 1.0//EN",
            systemID: "xhtml1.dtd",
            internalSubset: "<!ENTITY x \"y\">",
        )
        #expect(doctype.kind == .doctype)
        #expect(doctype.doctypeName == "html")
        #expect(doctype.publicID == "-//W3C//DTD XHTML 1.0//EN")
        #expect(doctype.systemID == "xhtml1.dtd")
        #expect(doctype.internalSubset == "<!ENTITY x \"y\">")
        #expect(doctype.stringValue.isEmpty)
    }

    @Test("A doctype child drops out of the content projection")
    func test_doctypeNotProjected() {
        let document = Tree.document(children: [
            Tree.doctype(name: "html"),
            Tree.element("html"),
        ])
        guard case let .document(children) = document.node else { Issue.record("not a document")
            return
        }
        #expect(children.count == 1)
        #expect(children.first == .element(.init(name: .init("html"))))
    }

    @Test("An entity-reference node splices its replacement into the content")
    func test_entityReferenceProjection() {
        let reference = Tree.entityReference("ref", children: [Tree.element("b"), Tree.text("tail")])
        let element = Tree.element("a", children: [Tree.text("head"), reference])
        #expect(reference.entityReferenceName == "ref")
        #expect(element.stringValue == "headtail")
        guard case let .element(projected) = element.node else { Issue.record("not an element")
            return
        }
        #expect(projected.children == [.text("head"), .element(.init(name: .init("b"))), .text("tail")])
    }

    @Test("A namespace node binds a prefix to a URI")
    func test_namespaceNode() {
        let bound = Tree.namespace(prefix: "p", uri: "urn:x")
        #expect(bound.kind == .namespace)
        #expect(bound.namespacePrefix == "p")
        #expect(bound.namespaceBinding == "urn:x")
        #expect(bound.stringValue == "urn:x")
        let defaultNS = Tree.namespace(prefix: "", uri: "urn:d")
        #expect(defaultNS.namespacePrefix == nil)
        #expect(defaultNS.namespaceBinding == "urn:d")
    }

    @Test("ownerDocument is the document root, or nil when detached")
    func test_ownerDocument() {
        let child = Tree.element("b")
        let document = Tree.document(children: [Tree.element("a", children: [child])])
        #expect(child.ownerDocument === document)
        child.removeFromParent()
        #expect(child.ownerDocument == nil)
        // A subtree not rooted at a document has no owner document.
        let loose = Tree.element("a", children: [Tree.element("b")])
        #expect(loose.children[0].ownerDocument == nil)
    }

    @Test("adopt detaches a node and re-declares its inherited namespaces")
    func test_adoptRebindsNamespaces() throws {
        let source = try PureXML.parseTree("<root xmlns:p=\"urn:x\"><p:child p:k=\"v\"/></root>")
        let child = source.children[0].children[0]
        #expect(child.attributeValue("xmlns:p") == nil)
        let target = Tree.document()
        let adopted = target.adopt(child)
        #expect(adopted.parent == nil)
        // The prefix that was declared on the outer <root> now travels with the node.
        #expect(adopted.attributeValue("xmlns:p") == "urn:x")
    }

    @Test("importNode copies a self-contained subtree without moving the original")
    func test_importNode() throws {
        let source = try PureXML.parseTree("<root xmlns:p=\"urn:x\"><p:child/></root>")
        let child = source.children[0].children[0]
        let target = Tree.document()
        let imported = target.importNode(child)
        #expect(imported !== child)
        #expect(child.parent === source.children[0]) // original stays put
        #expect(imported.attributeValue("xmlns:p") == "urn:x")
    }
}
