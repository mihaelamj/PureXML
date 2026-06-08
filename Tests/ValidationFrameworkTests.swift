@testable import PureXML
import Testing

/// Unit tests for the validation framework primitives: the `Validation` value,
/// the erased wrapper's type guard, and the combinator algebra exercised as pure
/// functions against hand-built contexts (no full traversal).
@Suite("Validation framework")
struct ValidationFrameworkTests {
    private typealias Element = PureXML.Model.Element
    private typealias Error = PureXML.Validation.ValidationError
    private typealias Context = PureXML.Validation.ValidationContext<PureXML.Model.Element, Void>

    private func context(_ element: Element, path: [PureXML.Validation.PathKey] = []) -> Context {
        Context(document: (), subject: element, codingPath: path)
    }

    private let sample = PureXML.Model.Element("e", attributes: [.init("a", "1")])

    @Test("The single-error Bool form auto-formats the failure")
    func test_boolForm() {
        let rule = PureXML.Validation.Validation<Element, Void>(
            description: "Element is named box",
            check: \Element.name.localName == "box",
        )
        #expect(rule.apply(to: sample, at: [.element("e")], in: ()).first?.reason == "Failed to satisfy: Element is named box")
        let box = PureXML.Model.Element("box")
        #expect(rule.apply(to: box, at: [], in: ()).isEmpty)
    }

    @Test("The predicate gates the check")
    func test_predicateGate() {
        var ran = false
        let rule = PureXML.Validation.Validation<Element, Void>(
            description: "never",
            check: { _ in ran = true
                return []
            },
            when: \Element.name.localName == "other",
        )
        _ = rule.apply(to: sample, at: [], in: ())
        #expect(ran == false)
    }

    @Test("The erased wrapper fires only on the exact type")
    func test_erasureTypeGuard() {
        let rule = PureXML.Validation.Validation<Element, Void>(description: "always fails", check: { _ in false })
        let erased = PureXML.Validation.AnyValidation(rule)
        // Wrong type yields no errors.
        #expect(erased.apply(to: "a string", at: [], in: ()).isEmpty)
        // An optional wrapping the type must not satisfy a non-optional validation.
        let optional: Element? = sample
        #expect(erased.apply(to: optional as Any, at: [], in: ()).isEmpty)
        // The exact type runs.
        #expect(erased.apply(to: sample, at: [], in: ()).count == 1)
    }

    @Test("&& concatenates both error lists; || short-circuits")
    func test_andOr() {
        let fail: (Context) -> [Error] = { [Error(reason: "x", at: $0.codingPath)] }
        let pass: (Context) -> [Error] = { _ in [] }
        #expect((fail && fail)(context(sample)).count == 2)
        #expect((pass || fail)(context(sample)).isEmpty)
        #expect((fail || fail)(context(sample)).count == 2)
    }

    @Test("take digs to a value and runs logic")
    func test_take() {
        let check: (Context) -> Bool = take(\Element.attributes) { $0.count == 1 }
        #expect(check(context(sample)))
        #expect(!check(context(PureXML.Model.Element("e"))))
    }

    @Test("all applies many validations to the same context")
    func test_all() {
        let one = PureXML.Validation.Validation<Element, Void>(description: "one", check: { _ in false })
        let two = PureXML.Validation.Validation<Element, Void>(description: "two", check: { _ in false })
        let combined: (Context) -> [Error] = all(one, two)
        #expect(combined(context(sample, path: [.element("e")])).count == 2)
    }

    @Test("withoutValidating removes a rule by description")
    func test_withoutValidating() {
        let validator = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.Structural.uniqueAttributes)
        #expect(validator.validationDescriptions == ["Element attribute names are unique"])
        let stripped = validator.withoutValidating("Element attribute names are unique")
        #expect(stripped.validationDescriptions.isEmpty)
    }
}
