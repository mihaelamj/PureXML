@testable import PureXML
import Testing

/// Per-rule isolation tests (Validation rules misc).
@Suite("Validation rules misc")
struct ValidationRuleMiscTests {
    // MARK: HTML

    @Test("HTML.voidElementsAreEmpty accepts an empty void element")
    func test_htmlVoidElementsAreEmpty_succeeds() {
        let node = PureXML.Model.Node.document([.element(.init("br"))])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.HTML.voidElementsAreEmpty)
            .errors(for: node, in: ())
        #expect(errors.isEmpty)
    }

    @Test("HTML.requiredParent accepts li inside ul")
    func test_htmlRequiredParent_succeeds() {
        let node = PureXML.Model.Node.document([
            .element(.init("ul", children: [.element(.init("li"))])),
        ])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.HTML.requiredParent)
            .errors(for: node, in: ())
        #expect(errors.isEmpty)
    }

    @Test("HTML.uniqueIdentifiers accepts distinct ids")
    func test_htmlUniqueIdentifiers_succeeds() {
        let node = PureXML.Model.Node.document([
            .element(.init("a", attributes: [.init("id", "one")])),
            .element(.init("b", attributes: [.init("id", "two")])),
        ])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.HTML.uniqueIdentifiers)
            .errors(for: node, in: ())
        #expect(errors.isEmpty)
    }

    @Test("HTML.voidElementsAreEmpty rejects content inside a void element")
    func test_htmlVoidElementsAreEmpty() {
        let node = PureXML.Model.Node.document([.element(.init("br", children: [.text("no")]))])
        #expect(!PureXML.Validation.Validator<Void>.blank.validating(PureXML.Validation.HTML.voidElementsAreEmpty).errors(for: node, in: ()).isEmpty)
    }

    @Test("HTML.requiredParent rejects li outside ul/ol/menu")
    func test_htmlRequiredParent() {
        let node = PureXML.Model.Node.document([.element(.init("li"))])
        #expect(!PureXML.Validation.Validator<Void>.blank.validating(PureXML.Validation.HTML.requiredParent).errors(for: node, in: ()).isEmpty)
    }

    @Test("HTML.uniqueIdentifiers rejects duplicate id values")
    func test_htmlUniqueIdentifiers() {
        let node = PureXML.Model.Node.document([
            .element(.init("a", attributes: [.init("id", "dup")])),
            .element(.init("b", attributes: [.init("id", "dup")])),
        ])
        #expect(!PureXML.Validation.Validator<Void>.blank.validating(PureXML.Validation.HTML.uniqueIdentifiers).errors(for: node, in: ()).isEmpty)
    }

    // MARK: Conformance

    @Test("Conformance.matchesExpected reports a divergent actual value")
    func test_conformanceMatchesExpected() {
        let testCase = PureXML.Validation.ConformanceCase(name: "sample", actual: "bad", expected: "good")
        let errors = PureXML.Validation.BuiltinValidation.conformanceMatchesExpected.apply(to: testCase, at: [.element("sample")], in: ())
        #expect(errors.count == 1)
    }

    @Test("Conformance.matchesExpected accepts a matching actual value")
    func test_conformanceMatchesExpected_succeeds() {
        let testCase = PureXML.Validation.ConformanceCase(name: "sample", actual: "good", expected: "good")
        #expect(PureXML.Validation.BuiltinValidation.conformanceMatchesExpected.apply(to: testCase, at: [.element("sample")], in: ()).isEmpty)
    }

    // MARK: XSD streaming

    @Test("ComplexValidator.shallowValidity rejects empty content that carries a child")
    func test_xsdStreamingShallowValidity() {
        let validator = PureXML.Schema.ComplexValidator()
        let bad = PureXML.Schema.ResolvedElement(
            element: PureXML.Model.Element("v", children: [.element(.init("child"))]),
            type: .complex(PureXML.Schema.ComplexType(content: .empty)),
        )
        #expect(!PureXML.Validation.BuiltinValidation.xsdStreamingShallowValidity.apply(to: bad, at: [.element("v")], in: validator).isEmpty)
    }

    @Test("ComplexValidator.shallowValidity accepts an empty element against an empty type")
    func test_xsdStreamingShallowValidity_succeeds() {
        let validator = PureXML.Schema.ComplexValidator()
        let good = PureXML.Schema.ResolvedElement(
            element: PureXML.Model.Element("v"),
            type: .complex(PureXML.Schema.ComplexType(content: .empty)),
        )
        #expect(PureXML.Validation.BuiltinValidation.xsdStreamingShallowValidity.apply(to: good, at: [.element("v")], in: validator).isEmpty)
    }

    // MARK: Machinery

    private struct Named: PureXML.Validation.Validatable {
        var name: String
    }

    private struct NamedDocument {
        var items: [String: Named] = [:]
    }

    @Test("lookup resolves a document entry and validates it")
    func test_lookupCombinator() {
        var document = NamedDocument(items: ["a": Named(name: "ok")])
        let rule = PureXML.Validation.Validation<Named, NamedDocument>(
            description: "Name is ok",
            check: \Named.name == "ok",
        )
        let lookupRule = PureXML.Validation.Validation<Named, NamedDocument>(
            description: "Named item resolves",
            check: lookup(\.items, name: \Named.name, missing: { "missing \($0)" }, into: rule),
        )
        let hit = lookupRule.apply(to: Named(name: "a"), at: [.element("a")], in: document)
        #expect(hit.isEmpty)
        let miss = lookupRule.apply(to: Named(name: "z"), at: [.element("z")], in: document)
        #expect(miss.count == 1)
        #expect(miss[0].reason == "missing z")
        document.items["bad"] = Named(name: "nope")
        let bad = lookupRule.apply(to: Named(name: "bad"), at: [.element("bad")], in: document)
        #expect(bad.first?.reason == "Failed to satisfy: Name is ok")
    }

    @Test("Validator.outcome collects errors without throwing")
    func test_validationOutcome() {
        let element = PureXML.Model.Element("a", attributes: [.init("x", "1"), .init("x", "2")])
        let node = PureXML.Model.Node.document([.element(element)])
        let outcome = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.Structural.uniqueAttributes)
            .outcome(for: node, in: ())
        #expect(!outcome.isValid)
        #expect(outcome.errors.count == 1)
    }
}
