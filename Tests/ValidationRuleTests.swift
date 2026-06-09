@testable import PureXML
import Testing

/// Per-rule isolation tests in the OpenAPIKit style: each builtin validation is
/// installed alone on a `blank` validator, run against a seeded subject, and the
/// resulting errors are asserted by count, reason, and coding path.
@Suite("Validation rules in isolation")
struct ValidationRuleTests {
    private typealias DTDSchema = PureXML.Validation.DTDSchema
    private typealias XSDContext = PureXML.Validation.XSDContext

    private func dtd(_ xml: String) throws -> (PureXML.Model.Node, DTDSchema) {
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(xml, limits: .init(allowDoctype: true))
        return (parsed.node, DTDSchema(parsed.documentType))
    }

    private func path(_ error: PureXML.Validation.ValidationError) -> [String] {
        error.codingPath.map(\.stringValue)
    }

    // MARK: Structural

    @Test("Structural.uniqueAttributes reports each duplicate at the element path")
    func test_uniqueAttributes() {
        let element = PureXML.Model.Element("a", attributes: [.init("x", "1"), .init("x", "2")])
        let node = PureXML.Model.Node.document([.element(element)])
        let errors = PureXML.Validation.Validator<Void>.blank
            .validating(PureXML.Validation.Structural.uniqueAttributes)
            .errors(for: node, in: ())
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Duplicate attribute 'x' on <a>")
        #expect(path(errors[0]) == ["a"])
    }

    // MARK: DTD

    @Test("DTD.contentModel reports an EMPTY element with content at the element path")
    func test_contentModel() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r><c/></r>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.contentModel)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "element <r> is declared EMPTY but has content")
        #expect(path(errors[0]) == ["r"])
    }

    @Test("DTD.requiredAttributes reports a missing required attribute in isolation")
    func test_requiredAttributes() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #REQUIRED>]><r/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.requiredAttributes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "required attribute 'id' is missing on <r>")
        #expect(path(errors[0]) == ["r"])
    }

    @Test("DTD.fixedAttributeValues isolates the #FIXED constraint")
    func test_fixedAttributeValues() throws {
        // A missing required attribute is invisible to the fixed-value rule alone.
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r v CDATA #FIXED \"1\" id CDATA #REQUIRED>]><r v=\"2\"/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.fixedAttributeValues)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "attribute 'v' on <r> is #FIXED and must be \"1\"")
    }

    @Test("DTD.enumeratedAttributeValues isolates the enumeration constraint")
    func test_enumeratedAttributeValues() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r k (a|b) #IMPLIED>]><r k=\"z\"/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.enumeratedAttributeValues)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "attribute 'k' on <r> has a value outside its enumeration")
    }

    @Test("DTD.tokenizedAttributeTypes isolates the NMTOKEN constraint")
    func test_tokenizedAttributeTypes() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r t NMTOKEN #IMPLIED>]><r t=\"a b\"/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.tokenizedAttributeTypes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("NMTOKEN") == true)
    }

    @Test("DTD.notationAttributes isolates the NOTATION constraint")
    func test_notationAttributes() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r kind NOTATION (bmp) #IMPLIED>]><r kind=\"bmp\"/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.notationAttributes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("undeclared notation") == true)
    }

    @Test("DTD.undeclaredElement uses the single-error Bool form (Failed to satisfy)")
    func test_undeclaredElement() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ELEMENT a EMPTY>]><r/>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.undeclaredElement)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Failed to satisfy: Element is declared in the DTD")
        #expect(path(errors[0]) == ["r"])
    }

    @Test("DTD.identifierIntegrity reports a duplicate ID at the document root")
    func test_identifierIntegrity() throws {
        let (node, schema) = try dtd("<!DOCTYPE r [<!ATTLIST a id ID #IMPLIED>]><r><a id=\"x\"/><a id=\"x\"/></r>")
        let errors = PureXML.Validation.Validator<DTDSchema>.blank
            .validating(PureXML.Validation.DTD.identifierIntegrity)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "duplicate ID 'x' (declared 2 times)")
        // Runs once over the whole tree, so it is located at the document root.
        #expect(path(errors[0]).isEmpty)
        #expect(String(describing: errors[0]).hasSuffix("at root of document"))
    }

    // MARK: XSD

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
        let context = XSDContext(
            types: compiled.types,
            constraints: compiled.constraints,
            rootDeclaration: compiled.elements["n"],
        )
        // The validator is rooted at the document element, as Schema.Document does.
        let errors = PureXML.Validation.Validator<XSDContext>.blank
            .validating(PureXML.Validation.XSD.contentValidity)
            .errors(for: .element(root), in: context)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("n") == true)
        #expect(errors.first.map(path) == ["n"])
    }
}
