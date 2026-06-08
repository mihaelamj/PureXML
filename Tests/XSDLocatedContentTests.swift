@testable import PureXML
import Testing

@Suite("XSD located content-model errors")
struct XSDLocatedContentTests {
    private typealias Schema = PureXML.Schema
    private typealias Name = PureXML.Model.QualifiedName

    private func element(_ name: String, children: [PureXML.Model.Node] = []) -> PureXML.Model.Element {
        PureXML.Model.Element(name: Name(localName: name), attributes: [], children: children)
    }

    private func validate(_ element: PureXML.Model.Element, _ type: Schema.ComplexType) -> [PureXML.Validation.ValidationError] {
        Schema.ComplexValidator().validate(element, against: type)
    }

    private func sequence(_ names: [String]) -> Schema.ComplexType {
        let particles = names.map { Schema.Particle(term: .element(name: Name(localName: $0), type: nil)) }
        return Schema.ComplexType(content: .elementOnly(Schema.Particle(term: .group(Schema.Group(compositor: .sequence, particles: particles)))))
    }

    @Test("An unexpected child is located with the expected element named")
    func test_unexpectedLocated() {
        let type = sequence(["a", "b"])
        let bad = element("root", children: [.element(element("a")), .element(element("x"))])
        let failure = validate(bad, type).first
        #expect(failure?.reason == "element 'x' is not allowed here; expected <b>")
        #expect(failure?.codingPath.map(\.stringValue) == ["x"])
    }

    @Test("Missing required content reports what was expected, at the element")
    func test_incompleteLocated() {
        let type = sequence(["a", "b"])
        let bad = element("root", children: [.element(element("a"))])
        let failure = validate(bad, type).first
        #expect(failure?.reason == "content is incomplete; expected <b>")
        #expect(failure?.codingPath.isEmpty == true)
    }

    @Test("A valid sequence produces no content errors")
    func test_valid() {
        let type = sequence(["a", "b"])
        let good = element("root", children: [.element(element("a")), .element(element("b"))])
        #expect(validate(good, type).isEmpty)
    }

    @Test("An xs:all group reports every stray child and every missing member (recovery)")
    func test_allRecovery() {
        let members = ["a", "b"].map {
            Schema.Particle(minOccurs: 1, maxOccurs: 1, term: .element(name: Name(localName: $0), type: nil))
        }
        let type = Schema.ComplexType(content: .elementOnly(Schema.Particle(term: .group(Schema.Group(compositor: .all, particles: members)))))
        // Two stray children, and member b never appears: three located problems.
        let bad = element("root", children: [.element(element("x")), .element(element("y")), .element(element("a"))])
        let reasons = validate(bad, type).map(\.reason)
        #expect(reasons.contains { $0.contains("'x'") && $0.contains("not allowed") })
        #expect(reasons.contains { $0.contains("'y'") && $0.contains("not allowed") })
        #expect(reasons.contains { $0.contains("'b'") && $0.contains("required but missing") })
    }
}
