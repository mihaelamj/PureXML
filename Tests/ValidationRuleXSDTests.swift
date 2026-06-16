@testable import PureXML
import Testing

/// Per-rule isolation tests (Validation rules XSD).
@Suite("Validation rules XSD")
struct ValidationRuleXSDTests {
    @Test("XSD.contentValidity locates a simple-type violation at the root element")
    func test_xsdContentValidity() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="n" type="xs:integer"/>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let node = try PureXML.parse("<n>x</n>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root element")
            return
        }
        let context = ValidationRuleTestSupport.XSDContext(
            types: compiled.types,
            constraints: compiled.constraints,
            rootDeclaration: compiled.elements["n"],
        )
        // The validator is rooted at the document element, as Schema.Document does.
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.XSDContext>.blank
            .validating(PureXML.Validation.XSD.contentValidity)
            .errors(for: .element(root), in: context)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("n") == true)
        #expect(errors.first.map(ValidationRuleTestSupport.path) == ["n"])
    }

    @Test("XSD.contentValidity accepts a valid integer at the boundary")
    func test_xsdContentValidity_succeeds() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="n" type="xs:integer"/>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let node = try PureXML.parse("<n>0</n>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root element")
            return
        }
        let context = ValidationRuleTestSupport.XSDContext(types: compiled.types, constraints: compiled.constraints, rootDeclaration: compiled.elements["n"])
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.XSDContext>.blank
            .validating(PureXML.Validation.XSD.contentValidity)
            .errors(for: .element(root), in: context)
        #expect(errors.isEmpty)
    }

    @Test("XSD.identityConstraints reports a duplicate key field")
    func test_xsdIdentityConstraints() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" maxOccurs="unbounded"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element></xs:sequence>
            </xs:complexType>
            <xs:unique name="byId"><xs:selector xpath="item"/><xs:field xpath="@id"/></xs:unique>
          </xs:element>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let node = try PureXML.parse("<list><item id=\"1\"/><item id=\"1\"/></list>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            Issue.record("no root element")
            return
        }
        let context = ValidationRuleTestSupport.XSDContext(types: compiled.types, constraints: compiled.constraints, rootDeclaration: compiled.elements["list"])
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.XSDContext>.blank
            .validating(PureXML.Validation.XSD.identityConstraints)
            .errors(for: .element(root), in: context)
        #expect(!errors.isEmpty)
    }

    @Test("XSD.identityConstraints accepts distinct field values")
    func test_xsdIdentityConstraints_succeeds() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="list">
            <xs:complexType>
              <xs:sequence><xs:element name="item" maxOccurs="unbounded"><xs:complexType><xs:attribute name="id" type="xs:string"/></xs:complexType></xs:element></xs:sequence>
            </xs:complexType>
            <xs:unique name="byId"><xs:selector xpath="item"/><xs:field xpath="@id"/></xs:unique>
          </xs:element>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let node = try PureXML.parse("<list><item id=\"1\"/><item id=\"2\"/></list>")
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else { return }
        let context = ValidationRuleTestSupport.XSDContext(types: compiled.types, constraints: compiled.constraints, rootDeclaration: compiled.elements["list"])
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.XSDContext>.blank.validating(PureXML.Validation.XSD.identityConstraints).errors(
            for: .element(root),
            in: context,
        ).isEmpty)
    }

    @Test("XSDSchema.finalRespected rejects a derivation forbidden by final")
    func test_xsdFinalRespected() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT" final="extension">
            <xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence>
          </xs:complexType>
          <xs:complexType name="CircleT">
            <xs:complexContent><xs:extension base="ShapeT"><xs:sequence><xs:element name="radius" type="xs:integer"/></xs:sequence></xs:extension></xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let facts = PureXML.Schema.CompiledSchemaFacts(types: compiled.types, typeDerivation: compiled.typeDerivation, typeFinal: compiled.typeFinal)
        let fact = PureXML.Schema.SchemaTypeFact(name: "CircleT", derivation: compiled.typeDerivation["CircleT"])
        let errors = PureXML.Validation.BuiltinValidation.xsdFinalRespected.apply(to: fact, at: [.element("CircleT")], in: facts)
        #expect(errors.count == 1)
    }

    @Test("XSDSchema.finalRespected accepts a derivation the base permits")
    func test_xsdFinalRespected_succeeds() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="ShapeT"><xs:sequence><xs:element name="name" type="xs:string"/></xs:sequence></xs:complexType>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let facts = PureXML.Schema.CompiledSchemaFacts(types: compiled.types, typeDerivation: compiled.typeDerivation, typeFinal: compiled.typeFinal)
        let fact = PureXML.Schema.SchemaTypeFact(name: "ShapeT", derivation: nil)
        #expect(PureXML.Validation.BuiltinValidation.xsdFinalRespected.apply(to: fact, at: [.element("ShapeT")], in: facts).isEmpty)
    }

    @Test("XSDSchema.restrictionsAreSubsets rejects an unfaithful restriction")
    func test_xsdRestrictionsAreSubsets() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="B"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
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
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let facts = PureXML.Schema.CompiledSchemaFacts(types: compiled.types, typeDerivation: compiled.typeDerivation, typeFinal: compiled.typeFinal)
        let fact = PureXML.Schema.SchemaTypeFact(name: "R", derivation: compiled.typeDerivation["R"])
        #expect(!PureXML.Validation.BuiltinValidation.xsdRestrictionsAreSubsets.apply(to: fact, at: [.element("R")], in: facts).isEmpty)
    }

    @Test("XSDSchema.restrictionsAreSubsets accepts a faithful restriction")
    func test_xsdRestrictionsAreSubsets_succeeds() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:complexType name="B"><xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence></xs:complexType>
          <xs:complexType name="R">
            <xs:complexContent>
              <xs:restriction base="B">
                <xs:sequence><xs:element name="a" type="xs:string"/></xs:sequence>
              </xs:restriction>
            </xs:complexContent>
          </xs:complexType>
        </xs:schema>
        """
        let compiled = try PureXML.Schema.XSDParser.parse(xsd)
        let facts = PureXML.Schema.CompiledSchemaFacts(types: compiled.types, typeDerivation: compiled.typeDerivation, typeFinal: compiled.typeFinal)
        let fact = PureXML.Schema.SchemaTypeFact(name: "R", derivation: compiled.typeDerivation["R"])
        #expect(PureXML.Validation.BuiltinValidation.xsdRestrictionsAreSubsets.apply(to: fact, at: [.element("R")], in: facts).isEmpty)
    }
}
