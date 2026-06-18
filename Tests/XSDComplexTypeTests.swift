import Testing
@testable import PureXML

@Suite("XSD complex types")
struct XSDComplexTypeTests {
    private typealias Schema = PureXML.Schema

    private func element(_ name: String, type: Schema.ElementType? = nil, min: Int = 1, max: Int? = 1) -> Schema.Particle {
        Schema.Particle(minOccurs: min, maxOccurs: max, term: .element(name: .init(name), type: type, typeName: nil))
    }

    private func parse(_ xml: String) throws -> PureXML.Model.Element {
        guard case let .document(children) = try PureXML.parse(xml), let root = children.compactMap(\.element).first else {
            throw TestFailure.noRoot
        }
        return root
    }

    private enum TestFailure: Error { case noRoot }

    private func validate(_ xml: String, _ type: Schema.ComplexType) throws -> [PureXML.Validation.ValidationError] {
        try Schema.ComplexValidator().validate(parse(xml), against: type)
    }

    // MARK: Sequence and occurrence

    @Test("A sequence accepts the declared order and occurrence")
    func test_sequence() throws {
        let type = Schema.ComplexType(content: .elementOnly(
            Schema.Particle(term: .group(.init(compositor: .sequence, particles: [
                element("title"),
                element("author", min: 1, max: nil),
            ]))),
        ))
        #expect(try validate("<book><title>T</title><author>A</author><author>B</author></book>", type).isEmpty)
        #expect(try !validate("<book><author>A</author><title>T</title></book>", type).isEmpty)
        #expect(try !validate("<book><title>T</title></book>", type).isEmpty)
    }

    @Test("A choice accepts exactly one alternative")
    func test_choice() throws {
        let type = Schema.ComplexType(content: .elementOnly(
            Schema.Particle(term: .group(.init(compositor: .choice, particles: [element("a"), element("b")]))),
        ))
        #expect(try validate("<r><a/></r>", type).isEmpty)
        #expect(try validate("<r><b/></r>", type).isEmpty)
        #expect(try !validate("<r><a/><b/></r>", type).isEmpty)
    }

    @Test("An all group accepts any order, each member once")
    func test_all() throws {
        let type = Schema.ComplexType(content: .elementOnly(
            Schema.Particle(term: .group(.init(compositor: .all, particles: [
                element("x"),
                element("y", min: 0, max: 1),
            ]))),
        ))
        #expect(try validate("<r><y/><x/></r>", type).isEmpty)
        #expect(try validate("<r><x/></r>", type).isEmpty)
        #expect(try !validate("<r><x/><x/></r>", type).isEmpty)
        #expect(try !validate("<r><y/></r>", type).isEmpty)
    }

    // MARK: Attributes

    @Test("Required and typed attributes are enforced")
    func test_attributes() throws {
        let type = Schema.ComplexType(
            attributes: [
                .init(name: .init("id"), type: .init(base: .int), required: true),
                .init(name: .init("lang"), type: .init(base: .language)),
            ],
            content: .empty,
        )
        #expect(try validate("<e id=\"1\" lang=\"en\"/>", type).isEmpty)
        #expect(try !validate("<e/>", type).isEmpty) // missing required id
        #expect(try !validate("<e id=\"x\"/>", type).isEmpty) // id not an int
        #expect(try !validate("<e id=\"1\" extra=\"y\"/>", type).isEmpty) // undeclared attribute
    }

    // MARK: Simple and mixed content

    @Test("Simple content validates the text against a simple type")
    func test_simpleContent() throws {
        let type = Schema.ComplexType(content: .simpleContent(.init(base: .int)))
        #expect(try validate("<n>42</n>", type).isEmpty)
        #expect(try !validate("<n>x</n>", type).isEmpty)
        #expect(try !validate("<n><child/></n>", type).isEmpty)
    }

    @Test("Element-only content rejects stray text; mixed allows it")
    func test_elementOnlyVsMixed() throws {
        let particle = Schema.Particle(term: .group(.init(compositor: .sequence, particles: [element("a")])))
        let elementOnly = Schema.ComplexType(content: .elementOnly(particle))
        let mixed = Schema.ComplexType(content: .mixed(particle))
        #expect(try !validate("<r>text<a/></r>", elementOnly).isEmpty)
        #expect(try validate("<r>text<a/></r>", mixed).isEmpty)
    }

    // MARK: Recursion

    @Test("Child elements are validated against their declared types")
    func test_recursiveTypes() throws {
        let count = Schema.ElementType.simple(.init(base: .nonNegativeInteger))
        let type = Schema.ComplexType(content: .elementOnly(
            Schema.Particle(term: .group(.init(compositor: .sequence, particles: [
                element("count", type: count),
            ]))),
        ))
        #expect(try validate("<r><count>3</count></r>", type).isEmpty)
        #expect(try !validate("<r><count>-1</count></r>", type).isEmpty)
    }
}
