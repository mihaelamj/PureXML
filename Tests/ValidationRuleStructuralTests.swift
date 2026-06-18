import Testing
@testable import PureXML

/// Per-rule isolation tests (Validation rules structural).
@Suite("Validation rules structural")
struct ValidationRuleStructuralTests {
    @Test("Structural.uniqueAttributes reports each duplicate at the element path")
    func test_uniqueAttributes() {
        let element = PureXML.Model.Element("a", attributes: [.init("x", "1"), .init("x", "2")])
        let node = PureXML.Model.Node.document([.element(element)])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.Structural.uniqueAttributes)
            .errors(for: node, in: ())
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Duplicate attribute 'x' on <a>")
        #expect(ValidationRuleTestSupport.path(errors[0]) == ["a"])
    }

    @Test("Structural.uniqueAttributes accepts distinct attribute names")
    func test_uniqueAttributes_succeeds() {
        let node = PureXML.Model.Node.document([.element(.init("a", attributes: [.init("x", "1"), .init("y", "2")]))])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.Structural.uniqueAttributes)
            .errors(for: node, in: ())
        #expect(errors.isEmpty)
    }
}
