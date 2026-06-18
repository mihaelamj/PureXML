import Testing
@testable import PureXML

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

    @Test("The Bool forms of && and || combine predicates")
    func test_andOrBool() {
        let yes: (Context) -> Bool = { _ in true }
        let nope: (Context) -> Bool = { _ in false }
        #expect((yes && yes)(context(sample)))
        #expect(!(yes && nope)(context(sample)))
        #expect((yes || nope)(context(sample)))
        #expect(!(nope || nope)(context(sample)))
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

    // MARK: Combinators against a hand-built context

    private struct Parent: PureXML.Validation.Validatable {
        var child = PureXML.Model.Element("c")
        var maybe: PureXML.Model.Element?
        var count = 2
    }

    private typealias ParentContext = PureXML.Validation.ValidationContext<Parent, Void>

    private func parentContext(_ parent: Parent) -> ParentContext {
        ParentContext(document: (), subject: parent, codingPath: [])
    }

    @Test("The comparison operators lift a KeyPath and a literal into a predicate")
    func test_comparisonOperators() {
        let greater: (ParentContext) -> Bool = \Parent.count > 1
        let atLeast: (ParentContext) -> Bool = \Parent.count >= 2
        let less: (ParentContext) -> Bool = \Parent.count < 5
        let atMost: (ParentContext) -> Bool = \Parent.count <= 2
        let notEqual: (ParentContext) -> Bool = \Parent.count != 3
        #expect(greater(parentContext(Parent(count: 2))))
        #expect(!greater(parentContext(Parent(count: 0))))
        #expect(atLeast(parentContext(Parent(count: 2))))
        #expect(less(parentContext(Parent(count: 2))))
        #expect(atMost(parentContext(Parent(count: 2))))
        #expect(notEqual(parentContext(Parent(count: 2))))
    }

    @Test("lift runs child-typed validations against a lifted value")
    func test_lift() {
        let childNamedC = PureXML.Validation.Validation<Element, Void>(
            description: "child is named c",
            check: \Element.name.localName == "c",
        )
        let lifted: (ParentContext) -> [Error] = lift(\Parent.child, into: childNamedC)
        #expect(lifted(parentContext(Parent())).isEmpty)
        #expect(lifted(parentContext(Parent(child: Element("d")))).count == 1)
    }

    @Test("unwrap errors on nil and otherwise runs child validations")
    func test_unwrap() {
        let alwaysFails = PureXML.Validation.Validation<Element, Void>(description: "no", check: { _ in false })
        let rule: (ParentContext) -> [Error] = unwrap(\Parent.maybe, into: alwaysFails)
        let onNil = rule(parentContext(Parent(maybe: nil)))
        #expect(onNil.count == 1)
        #expect(onNil.first?.reason.contains("nil") == true)
        let onValue = rule(parentContext(Parent(maybe: Element("m"))))
        #expect(onValue.count == 1)
    }

    @Test("The same value of the same type applied twice yields two errors")
    func test_erasureAppliedTwice() {
        let rule = PureXML.Validation.Validation<Element, Void>(description: "always fails", check: { _ in false })
        let erased = PureXML.Validation.AnyValidation(rule)
        let atA = erased.apply(to: sample, at: [.element("a")], in: ())
        let atB = erased.apply(to: sample, at: [.element("b")], in: ())
        #expect((atA + atB).count == 2)
    }

    @Test("lookup resolves against the document store")
    func test_lookup() {
        struct Item: PureXML.Validation.Validatable { var key: String }
        struct Store { var items: [String: Item] = [:] }
        typealias Context = PureXML.Validation.ValidationContext<Item, Store>
        let rule: (Context) -> [PureXML.Validation.ValidationError] = lookup(
            \Store.items,
            name: \Item.key,
            missing: { "missing \($0)" },
            into: PureXML.Validation.Validation(description: "present", check: { _ in true }),
        )
        let store = Store(items: ["a": Item(key: "a")])
        let context = Context(document: store, subject: Item(key: "a"), codingPath: [])
        #expect(rule(context).isEmpty)
        let missing = Context(document: store, subject: Item(key: "z"), codingPath: [])
        #expect(rule(missing).count == 1)
    }

    @Test("Parameter-pack KeyPath validating mixes void-document builtins")
    func test_keyPathParameterPack() {
        let validator = PureXML.Validation.Validator<Void>.blank
            .validating(\.uniqueAttributes, \.htmlVoidElementsAreEmpty)
        #expect(validator.validationDescriptions == [
            "Element attribute names are unique",
            "Void HTML elements have no content",
        ])
    }

    @Test("Validator.outcome returns valid when no rules fail")
    func test_outcomeValid() {
        let node = PureXML.Model.Node.document([.element(.init("a"))])
        let outcome = PureXML.Validation.Validator<Void>().outcome(for: node, in: ())
        #expect(outcome.isValid)
    }
}
