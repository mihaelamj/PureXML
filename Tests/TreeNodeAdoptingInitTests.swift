import Testing
@testable import PureXML

/// `parseTree` materializes the mutable tree through `TreeNode.init(adopting:)`,
/// which adopts a prepared array of freshly built children and wires their
/// parents directly instead of appending them one at a time. These pin that the
/// adopted tree is indistinguishable from one built through `append`: every
/// child's `parent` points back to its container, sibling order is preserved,
/// and the tree stays correctly mutable afterwards (so the bypassed `append`
/// bookkeeping left nothing inconsistent).
@Suite("TreeNode adopting-init equivalence")
struct TreeNodeAdoptingInitTests {
    private static let source = #"""
    <catalog xmlns:m="urn:m">
      <item id="i0" m:rank="0"><name>first</name><price>1</price></item>
      <item id="i1"><name>second</name><note>a &amp; b</note></item>
    </catalog>
    """#

    private func assertParentsConsistent(_ node: PureXML.Model.TreeNode) {
        for child in node.children {
            #expect(child.parent === node)
            assertParentsConsistent(child)
        }
    }

    @Test("every child's parent points back to its container")
    func test_parentWiring() throws {
        let tree = try PureXML.parseTree(Self.source)
        #expect(tree.parent == nil)
        assertParentsConsistent(tree)
    }

    @Test("sibling order is preserved through adoption")
    func test_childOrder() throws {
        let tree = try PureXML.parseTree(Self.source)
        guard let catalog = tree.children.first(where: { $0.kind == .element }) else {
            Issue.record("no catalog")
            return
        }
        let items = catalog.children.filter { $0.kind == .element }
        #expect(items.count == 2)
        #expect(items[0].attributes.first { $0.name.localName == "id" }?.value == "i0")
        #expect(items[1].attributes.first { $0.name.localName == "id" }?.value == "i1")
        let firstItemChildren = items[0].children.filter { $0.kind == .element }.map { $0.name?.localName }
        #expect(firstItemChildren == ["name", "price"])
    }

    @Test("an adopted tree is still correctly mutable")
    func test_stillMutable() throws {
        let tree = try PureXML.parseTree(Self.source)
        guard let catalog = tree.children.first(where: { $0.kind == .element }),
              let firstItem = catalog.children.first(where: { $0.kind == .element })
        else {
            Issue.record("no item")
            return
        }
        let originalCount = catalog.children.count
        let added = PureXML.Model.TreeNode.element(PureXML.Model.QualifiedName("added"))
        catalog.append(added)
        #expect(added.parent === catalog)
        #expect(catalog.children.count == originalCount + 1)
        // Re-parenting a node already in the adopted tree detaches it cleanly.
        let secondItem = PureXML.Model.TreeNode.element(PureXML.Model.QualifiedName("wrapper"))
        catalog.append(secondItem)
        secondItem.append(firstItem)
        #expect(firstItem.parent === secondItem)
        #expect(!catalog.children.contains { $0 === firstItem })
    }
}
