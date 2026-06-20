import Testing
@testable import PureXML

/// Each XSD constraint category exercised against `ComplexValidator` directly with
/// crafted inputs, so it is verifiable on its own (the OpenAPIKit isolation recipe
/// applied to the inherently-recursive XSD validator; see XSDValidations.swift's
/// #101 scope note). Derivation, wildcards, and namespaces are isolation-tested
/// through crafted schema strings in their own suites.
@Suite("XSD constraint categories in isolation")
struct XSDCategoryTests {
    private typealias Schema = PureXML.Schema
    private typealias Name = PureXML.Model.QualifiedName

    private func element(_ name: String, _ attributes: [(String, String)] = [], children: [PureXML.Model.Node] = []) -> PureXML.Model.Element {
        PureXML.Model.Element(name, attributes: attributes.map { PureXML.Model.Attribute($0.0, $0.1) }, children: children)
    }

    private func validate(
        _ element: PureXML.Model.Element,
        _ type: Schema.ComplexType,
        validator: Schema.ComplexValidator = Schema.ComplexValidator(),
    ) -> [PureXML.Validation.ValidationError] {
        validator.validate(element, against: type, at: [.element(element.name.description)])
    }

    // MARK: Attributes

    @Test("Attributes: a required attribute is missing")
    func test_requiredMissing() {
        let type = Schema.ComplexType(attributes: [Schema.AttributeUse(name: Name("id"), type: Schema.SimpleType(base: .string), required: true)], content: .empty)
        let errors = validate(element("a"), type)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "missing required attribute 'id'")
        #expect(errors.first?.codingPath.map(\.stringValue) == ["a"])
    }

    @Test("Attributes: a fixed attribute must match")
    func test_fixedAttribute() {
        let use = Schema.AttributeUse(name: Name("v"), type: Schema.SimpleType(base: .string), valueConstraint: .fixed("1"))
        let type = Schema.ComplexType(attributes: [use], content: .empty)
        #expect(validate(element("a", [("v", "1")]), type).isEmpty)
        #expect(validate(element("a", [("v", "2")]), type).first?.reason.contains("fixed") == true)
    }

    @Test("Attributes: an undeclared attribute is rejected unless a wildcard admits it")
    func test_undeclaredAttribute() {
        let strict = Schema.ComplexType(content: .empty)
        #expect(validate(element("a", [("x", "1")]), strict).first?.reason == "undeclared attribute 'x'")
        let lax = Schema.ComplexType(attributeWildcard: Schema.Wildcard(namespace: .any, processContents: .skip), content: .empty)
        #expect(validate(element("a", [("x", "1")]), lax).isEmpty)
    }

    // MARK: Content

    @Test("Content: an EMPTY type rejects children")
    func test_emptyWithChildren() {
        let type = Schema.ComplexType(content: .empty)
        #expect(validate(element("a", children: [.element(element("b"))]), type).first?.reason == "element must be empty")
    }

    @Test("Content: simpleContent validates the text against its datatype")
    func test_simpleContent() {
        let type = Schema.ComplexType(content: .simpleContent(Schema.SimpleType(base: .integer)))
        #expect(validate(element("a", children: [.text("5")]), type).isEmpty)
        #expect(!validate(element("a", children: [.text("x")]), type).isEmpty)
    }

    @Test("Content: a child outside the content model is located with an expected hint")
    func test_contentModelMismatch() {
        let particle = Schema.Particle(term: .group(Schema.Group(compositor: .sequence, particles: [
            Schema.Particle(term: .element(name: Name("b"), type: nil, typeName: nil)),
        ])))
        let type = Schema.ComplexType(content: .elementOnly(particle))
        #expect(validate(element("a", children: [.element(element("b"))]), type).isEmpty)
        let failure = validate(element("a", children: [.element(element("c"))]), type).first
        #expect(failure?.reason == "element 'c' is not allowed here; expected <b>")
        #expect(failure?.codingPath.map(\.stringValue) == ["a", "c"])
    }

    // MARK: Nillable and fixed

    @Test("Nillable: xsi:nil on a non-nillable element is rejected")
    func test_notNillable() {
        let xsi = ("xsi:nil", "true")
        let type = Schema.ComplexType(content: .empty)
        // Default validator declares no nillable elements.
        #expect(validate(element("a", [xsi]), type).contains { $0.reason.contains("not nillable") })
        // A validator that declares it nillable accepts the empty nilled element.
        let nillable = Schema.ComplexValidator(nillableElements: ["a"])
        #expect(validate(element("a", [xsi]), type, validator: nillable).isEmpty)
    }

    @Test("Nillable: xsi:nil='false' is also forbidden on a non-nillable element (cvc-elt.3.1)")
    func test_notNillableNilFalse() {
        let nilFalse = ("xsi:nil", "false")
        let type = Schema.ComplexType(content: .empty)
        // cvc-elt.3.1: a non-nillable element must carry no xsi:nil attribute at all,
        // so even xsi:nil="false" is rejected (not only "true").
        #expect(validate(element("a", [nilFalse]), type).contains { $0.reason.contains("not nillable") })
        // A nillable element may carry xsi:nil="false" (explicitly not nilled): accepted.
        let nillable = Schema.ComplexValidator(nillableElements: ["a"])
        #expect(validate(element("a", [nilFalse]), type, validator: nillable).isEmpty)
    }

    @Test("Fixed: an element fixed value must match")
    func test_fixedElement() {
        let validator = Schema.ComplexValidator(elementConstraints: ["a": .fixed("yes")])
        let type = Schema.ComplexType(content: .simpleContent(Schema.SimpleType(base: .string)))
        #expect(validate(element("a", children: [.text("yes")]), type, validator: validator).isEmpty)
        #expect(validate(element("a", children: [.text("no")]), type, validator: validator).contains { $0.reason.contains("fixed") })
    }
}
