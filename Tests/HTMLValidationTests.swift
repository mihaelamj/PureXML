@testable import PureXML
import Testing

@Suite("HTML conformance validator (composable Validation rules)")
struct HTMLValidationTests {
    private typealias Element = PureXML.Model.Element
    private typealias Node = PureXML.Model.Node

    private func errors(_ node: Node) -> [PureXML.Validation.ValidationError] {
        PureXML.HTML.validationErrors(in: node)
    }

    @Test("A void element carrying content is flagged")
    func test_voidWithContent() {
        let node = Node.element(Element("br", children: [.text("x")]))
        let found = errors(node)
        #expect(found.count == 1)
        #expect(found.first?.reason == "void element <br> must not have content")
    }

    @Test("li inside ul is valid; li with no list parent is flagged")
    func test_requiredParent() {
        let valid = Node.document([.element(Element("ul", children: [.element(Element("li", children: [.text("a")]))]))])
        #expect(errors(valid).isEmpty)

        let invalid = Node.document([.element(Element("li", children: [.text("a")]))])
        let found = errors(invalid)
        #expect(found.count == 1)
        #expect(found.first?.reason == "element <li> must appear inside <menu>, <ol>, <ul>")
    }

    @Test("td must appear inside tr")
    func test_tableCellParent() {
        let invalid = Node.document([.element(Element("table", children: [.element(Element("td", children: [.text("x")]))]))])
        let found = errors(invalid)
        #expect(found.contains { $0.reason == "element <td> must appear inside <tr>" })
    }

    @Test("Duplicate id values are reported once each")
    func test_uniqueIdentifiers() {
        let div = Element("div", children: [
            .element(Element("p", attributes: [.init("id", "x")])),
            .element(Element("span", attributes: [.init("id", "x")])),
        ])
        let found = errors(.document([.element(div)]))
        #expect(found.count == 1)
        #expect(found.first?.reason == "duplicate id 'x' (used 2 times)")
    }

    @Test("A well-formed document passes")
    func test_valid() {
        let list = Element("ul", children: [
            .element(Element("li", attributes: [.init("id", "a")], children: [.text("one")])),
            .element(Element("li", attributes: [.init("id", "b")], children: [.text("two")])),
        ])
        #expect(errors(.document([.element(list)])).isEmpty)
    }

    // MARK: Each rule is composable and isolation-testable on its own.

    @Test("HTML.requiredParent runs in isolation")
    func test_requiredParentIsolated() {
        let node = Node.document([.element(Element("option", children: [.text("a")]))])
        let found = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.HTML.requiredParent)
            .errors(for: node, in: ())
        #expect(found.count == 1)
        #expect(found.first?.reason.contains("must appear inside") == true)
    }

    @Test("HTML.uniqueIdentifiers runs in isolation")
    func test_uniqueIdentifiersIsolated() {
        let node = Node.document([.element(Element("a", attributes: [.init("id", "z")])), .element(Element("b", attributes: [.init("id", "z")]))])
        let found = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.HTML.uniqueIdentifiers)
            .errors(for: node, in: ())
        #expect(found.count == 1)
    }
}
