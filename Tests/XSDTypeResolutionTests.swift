import Testing
@testable import PureXML

@Suite("XSD type resolution: unknown xsi:type and circular references")
struct XSDTypeResolutionTests {
    private let schema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:element name="r">
        <xs:complexType>
          <xs:sequence><xs:element name="v" type="xs:string"/></xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    @Test("An xsi:type naming an undeclared type is a located error, not a silent fallback")
    func test_unknownXsiType() throws {
        let xml = "<r xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><v xsi:type=\"Nope\">x</v></r>"
        let document = try PureXML.Schema.Document(schema)
        let tree = try document.validate(xml)
        #expect(tree.contains { $0.reason.contains("unknown xsi:type 'Nope'") }, "\(tree.map(\.reason))")
        // Streaming reports the same problem.
        let streamed = try document.validate(streaming: xml)
        #expect(streamed.contains { $0.reason.contains("unknown xsi:type 'Nope'") }, "\(streamed.map(\.reason))")
        // A known xsi:type still validates cleanly.
        let known = "<r xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><v>x</v></r>"
        try #expect(document.validate(known).isEmpty)
    }

    @Test("A circular typeReference chain is a located error, not silent truncation")
    func test_circularReference() {
        let validator = PureXML.Schema.ComplexValidator(
            types: ["A": .typeReference("B"), "B": .typeReference("A")],
        )
        let element = PureXML.Model.Element("e")
        let errors = validator.validate(element, as: .typeReference("A"), at: [.element("e")])
        #expect(errors.contains { $0.reason.contains("circular type reference") }, "\(errors.map(\.reason))")
        // The shallow (streaming) check reports it too, and terminates (this
        // previously recursed without bound on a cyclic table).
        let shallow = validator.validateShallow(element, as: .typeReference("A"), at: [.element("e")])
        #expect(shallow.contains { $0.reason.contains("circular type reference") }, "\(shallow.map(\.reason))")
    }

    @Test("The shared resolver distinguishes resolved, unknown, and circular")
    func test_resolver() {
        let types: [String: PureXML.Schema.ElementType] = [
            "Alias": .typeReference("Real"),
            "Real": .complex(PureXML.Schema.ComplexType(content: .empty)),
            "Loop": .typeReference("Loop"),
        ]
        if case .resolved = PureXML.Schema.ComplexValidator.resolveReference(.typeReference("Alias"), in: types) {} else {
            Issue.record("alias chain should resolve")
        }
        if case let .unknown(name) = PureXML.Schema.ComplexValidator.resolveReference(.typeReference("Missing"), in: types) {
            #expect(name == "Missing")
        } else {
            Issue.record("missing name should be unknown")
        }
        if case let .circular(name) = PureXML.Schema.ComplexValidator.resolveReference(.typeReference("Loop"), in: types) {
            #expect(name == "Loop")
        } else {
            Issue.record("self-reference should be circular")
        }
    }

    @Test("Conformance: the instance-override corpus passes through the harness")
    func test_conformanceCases() throws {
        let document = try PureXML.Schema.Document(schema)
        let bad = "<r xmlns:xsi=\"http://www.w3.org/2001/XMLSchema-instance\"><v xsi:type=\"Nope\">x</v></r>"
        let good = "<r><v>x</v></r>"
        let cases = try [
            PureXML.Validation.ConformanceCase(
                name: "unknown-xsi-type-rejected",
                actual: document.validate(bad).isEmpty ? "valid" : "invalid",
                expected: "invalid",
            ),
            PureXML.Validation.ConformanceCase(
                name: "plain-instance-accepted",
                actual: document.validate(good).isEmpty ? "valid" : "invalid",
                expected: "valid",
            ),
        ]
        let failures = PureXML.Validation.Conformance.failures(in: cases)
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
