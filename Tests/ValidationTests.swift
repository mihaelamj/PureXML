@testable import PureXML
import Testing

@Suite("Validation")
struct ValidationTests {
    @Test("Duplicate attribute is one located error")
    func test_duplicateAttributeIsError() {
        let element = PureXML.Model.Element(
            "input",
            attributes: [.init("id", "a"), .init("id", "b")],
        )
        let errors = PureXML.Validation.Validator().errors(for: .element(element))
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Duplicate attribute 'id' on <input>")
        #expect(errors.first?.codingPath.isEmpty == true)
    }

    @Test("Unique attributes validate cleanly")
    func test_uniqueAttributesValidate() throws {
        let element = PureXML.Model.Element(
            "input",
            attributes: [.init("id", "a"), .init("name", "b")],
        )
        try PureXML.validate(.element(element))
    }

    @Test("A located failure renders its coding path")
    func test_errorRendersPath() {
        let bad = PureXML.Model.Element("cell", attributes: [.init("id", "a"), .init("id", "b")])
        let root = PureXML.Model.Element("table", children: [
            .element(PureXML.Model.Element("row", children: [.element(bad)])),
        ])
        // Parse output is a document node, so the root element is named in the path.
        let errors = PureXML.Validation.Validator().errors(for: .document([.element(root)]))
        #expect(errors.count == 1)
        #expect(String(describing: errors[0]) == "Duplicate attribute 'id' on <cell> at path: table/row/cell")
    }

    @Test("Throwing form collects errors into one collection")
    func test_throwsCollection() {
        let element = PureXML.Model.Element("x", attributes: [.init("a", "1"), .init("a", "2")])
        #expect(throws: PureXML.Validation.ValidationErrorCollection.self) {
            try PureXML.validate(.element(element))
        }
    }

    @Test("A blank validator runs no rules")
    func test_blankValidator() {
        let element = PureXML.Model.Element("x", attributes: [.init("a", "1"), .init("a", "2")])
        let validator = PureXML.Validation.Validator<Void>.blank
        #expect(validator.errors(for: .element(element), in: ()).isEmpty)
    }
}
