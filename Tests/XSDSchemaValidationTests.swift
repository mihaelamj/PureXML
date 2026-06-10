@testable import PureXML
import Testing

/// Unit tests for the schema-consistency validation rules (final respected,
/// Particle Valid (Restriction)) exercised directly per the framework idiom,
/// plus the collected-findings behavior: a schema with several problems
/// reports them all at once instead of failing on the first.
@Suite("XSD schema-consistency validation")
struct XSDSchemaValidationTests {
    private typealias Fact = PureXML.Schema.SchemaTypeFact
    private typealias Facts = PureXML.Schema.CompiledSchemaFacts

    /// Compiles raw XSD source into the parser's tables, bypassing
    /// `Schema.Document`'s consistency throw, so the rules can be applied
    /// directly to known-inconsistent schemas.
    private func compile(_ xsd: String) throws -> PureXML.Schema.XSDCompiled {
        try PureXML.Schema.XSDParser.parse(xsd) { _ in nil }
    }

    private let finalViolationSchema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:complexType name="ShapeT" final="extension">
        <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
      </xs:complexType>
      <xs:complexType name="CircleT">
        <xs:complexContent>
          <xs:extension base="ShapeT">
            <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
          </xs:extension>
        </xs:complexContent>
      </xs:complexType>
      <xs:element name="s" type="CircleT"/>
    </xs:schema>
    """

    private let badRestrictionSchema = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
      <xs:complexType name="B">
        <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
      </xs:complexType>
      <xs:complexType name="R">
        <xs:complexContent>
          <xs:restriction base="B">
            <xs:sequence>
              <xs:element name="a" type="xs:string"/>
              <xs:element name="b" type="xs:string"/>
            </xs:sequence>
          </xs:restriction>
        </xs:complexContent>
      </xs:complexType>
      <xs:element name="r" type="R"/>
    </xs:schema>
    """

    @Test("finalRespected reports a derivation the base declares final, and only that")
    func test_finalRespectedRule() throws {
        let compiled = try compile(finalViolationSchema)
        let facts = Facts(types: compiled.types, typeFinal: compiled.typeFinal)
        let rule = PureXML.Validation.XSDSchema.finalRespected
        let bad = Fact(name: "CircleT", derivation: compiled.typeDerivation["CircleT"])
        let errors = rule.apply(to: bad, at: [.element("CircleT")], in: facts)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "type 'CircleT' derives from 'ShapeT' by extension, which 'ShapeT' declares final")
        // A type with no derivation at all is untouched by the rule.
        let underived = Fact(name: "ShapeT", derivation: nil)
        #expect(rule.apply(to: underived, at: [.element("ShapeT")], in: facts).isEmpty)
    }

    @Test("restrictionsAreSubsets reports an unfaithful restriction with the violation reason")
    func test_restrictionRule() throws {
        let compiled = try compile(badRestrictionSchema)
        let facts = Facts(types: compiled.types, typeFinal: compiled.typeFinal)
        let rule = PureXML.Validation.XSDSchema.restrictionsAreSubsets
        let bad = Fact(name: "R", derivation: compiled.typeDerivation["R"])
        let errors = rule.apply(to: bad, at: [.element("R")], in: facts)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("type 'R' is not a valid restriction of 'B'") == true)
        // The same rule passes a faithful restriction (identical content model).
        let faithful = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="B">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="R">
            <xs:complexContent>
              <xs:restriction base="B">
                <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="r" type="R"/>
        </xs:schema>
        """
        let good = try compile(faithful)
        let goodFacts = Facts(types: good.types, typeFinal: good.typeFinal)
        let goodFact = Fact(name: "R", derivation: good.typeDerivation["R"])
        #expect(rule.apply(to: goodFact, at: [.element("R")], in: goodFacts).isEmpty)
    }

    @Test("A schema with several consistency problems reports them all at once")
    func test_multiProblemSchemaReportsAll() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" final="extension">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent>
              <xs:extension base="ShapeT">
                <xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence>
              </xs:extension>
            </xs:complexContent>
          </xs:complexType>
          <xs:complexType name="B">
            <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="R">
            <xs:complexContent>
              <xs:restriction base="B">
                <xs:sequence>
                  <xs:element name="a" type="xs:string"/>
                  <xs:element name="b" type="xs:string"/>
                </xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
          <xs:element name="s" type="CircleT"/>
        </xs:schema>
        """
        do {
            _ = try PureXML.Schema.Document(xsd)
            Issue.record("compilation should have thrown")
        } catch let error as PureXML.Schema.SchemaError {
            guard case let .inconsistent(findings) = error else {
                Issue.record("expected .inconsistent, got \(error)")
                return
            }
            #expect(findings.count == 2)
            #expect(findings.contains { $0.contains("declares final") })
            #expect(findings.contains { $0.contains("not a valid restriction") })
        }
    }

    @Test("consistencyErrors walks every derived type in deterministic name order")
    func test_consistencyErrorsOrder() throws {
        let compiledFinal = try compile(finalViolationSchema)
        let compiledRestriction = try compile(badRestrictionSchema)
        let finalErrors = PureXML.Validation.XSDSchema.consistencyErrors(
            types: compiledFinal.types,
            typeDerivation: compiledFinal.typeDerivation,
            typeFinal: compiledFinal.typeFinal,
        )
        #expect(finalErrors.count == 1)
        #expect(finalErrors.first?.codingPath == [.element("CircleT")])
        let restrictionErrors = PureXML.Validation.XSDSchema.consistencyErrors(
            types: compiledRestriction.types,
            typeDerivation: compiledRestriction.typeDerivation,
            typeFinal: compiledRestriction.typeFinal,
        )
        #expect(restrictionErrors.count == 1)
        #expect(restrictionErrors.first?.codingPath == [.element("R")])
    }
}
