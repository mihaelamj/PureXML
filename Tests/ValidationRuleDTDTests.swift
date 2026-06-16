@testable import PureXML
import Testing

/// Per-rule isolation tests (Validation rules DTD).
@Suite("Validation rules DTD")
struct ValidationRuleDTDTests {
    @Test("DTD.contentModel reports an EMPTY element with content at the element path")
    func test_contentModel() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r><c/></r>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.contentModel)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "element <r> is declared EMPTY but has content")
        #expect(ValidationRuleTestSupport.path(errors[0]) == ["r"])
    }

    @Test("DTD.contentModel accepts an EMPTY element with no content")
    func test_dtdContentModel_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.contentModel)
            .errors(for: node, in: schema)
        #expect(errors.isEmpty)
    }

    @Test("DTD.requiredAttributes reports a missing required attribute in isolation")
    func test_requiredAttributes() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #REQUIRED>]><r/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.requiredAttributes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "required attribute 'id' is missing on <r>")
        #expect(ValidationRuleTestSupport.path(errors[0]) == ["r"])
    }

    @Test("DTD.fixedAttributeValues isolates the #FIXED constraint")
    func test_fixedAttributeValues() throws {
        // A missing required attribute is invisible to the fixed-value rule alone.
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r v CDATA #FIXED \"1\" id CDATA #REQUIRED>]><r v=\"2\"/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.fixedAttributeValues)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "attribute 'v' on <r> is #FIXED and must be \"1\"")
    }

    @Test("DTD.requiredAttributes accepts a present required attribute")
    func test_dtdRequiredAttributes_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #REQUIRED>]><r id=\"1\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.requiredAttributes).errors(for: node, in: schema).isEmpty)
    }

    @Test("DTD.fixedAttributeValues accepts the fixed value")
    func test_dtdFixedAttributeValues_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r v CDATA #FIXED \"1\">]><r v=\"1\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.fixedAttributeValues).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.enumeratedAttributeValues accepts a listed value")
    func test_dtdEnumeratedAttributeValues_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r k (a|b) #IMPLIED>]><r k=\"a\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.enumeratedAttributeValues).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.tokenizedAttributeTypes accepts a valid NMTOKEN")
    func test_dtdTokenizedAttributeTypes_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r t NMTOKEN #IMPLIED>]><r t=\"abc\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.tokenizedAttributeTypes).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.notationAttributes accepts a declared notation")
    func test_dtdNotationAttributes_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport
            .dtd("<!DOCTYPE r [<!NOTATION bmp SYSTEM \"b\"><!ELEMENT r EMPTY><!ATTLIST r kind NOTATION (bmp) #IMPLIED>]><r kind=\"bmp\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.notationAttributes).errors(for: node, in: schema).isEmpty)
    }

    @Test("DTD.enumeratedAttributeValues isolates the enumeration constraint")
    func test_enumeratedAttributeValues() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r k (a|b) #IMPLIED>]><r k=\"z\"/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.enumeratedAttributeValues)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "attribute 'k' on <r> has a value outside its enumeration")
    }

    @Test("DTD.tokenizedAttributeTypes isolates the NMTOKEN constraint")
    func test_tokenizedAttributeTypes() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r t NMTOKEN #IMPLIED>]><r t=\"a b\"/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.tokenizedAttributeTypes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("NMTOKEN") == true)
    }

    @Test("DTD.notationAttributes isolates the NOTATION constraint")
    func test_notationAttributes() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r kind NOTATION (bmp) #IMPLIED>]><r kind=\"bmp\"/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.notationAttributes)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("undeclared notation") == true)
    }

    @Test("DTD.undeclaredElement uses the single-error Bool form (Failed to satisfy)")
    func test_undeclaredElement() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT a EMPTY>]><r/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.undeclaredElement)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Failed to satisfy: Element is declared in the DTD")
        #expect(ValidationRuleTestSupport.path(errors[0]) == ["r"])
    }

    @Test("DTD.identifierIntegrity reports a duplicate ID at the document root")
    func test_identifierIntegrity() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ATTLIST a id ID #IMPLIED>]><r><a id=\"x\"/><a id=\"x\"/></r>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.identifierIntegrity)
            .errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "duplicate ID 'x' (declared 2 times)")
        // Runs once over the whole tree, so it is located at the document root.
        #expect(ValidationRuleTestSupport.path(errors[0]).isEmpty)
        #expect(String(describing: errors[0]).hasSuffix("at root of document"))
    }

    @Test("DTD.identifierIntegrity accepts unique IDs and resolved IDREFs")
    func test_dtdIdentifierIntegrity_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ATTLIST a id ID #IMPLIED ref IDREF #IMPLIED>]><r><a id=\"y\"/><a ref=\"y\"/></r>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.identifierIntegrity).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.undeclaredElement accepts a declared root element")
    func test_dtdUndeclaredElement_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.undeclaredElement).errors(for: node, in: schema).isEmpty)
    }

    @Test("DTD.undeclaredAttributes reports an attribute not declared in the DTD")
    func test_dtdUndeclaredAttributes() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r extra=\"1\"/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.undeclaredAttributes).errors(for: node, in: schema)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("extra") == true)
    }

    @Test("DTD.undeclaredAttributes accepts only declared attributes")
    func test_dtdUndeclaredAttributes_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #IMPLIED>]><r id=\"1\"/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.undeclaredAttributes).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.declarationValidity reports duplicate element declarations")
    func test_dtdDeclarationValidity() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ELEMENT x (#PCDATA)><!ELEMENT x (#PCDATA)>]><r/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.declarationValidity).errors(for: node, in: schema)
        #expect(errors.contains { $0.reason.contains("declared more than once") })
    }

    @Test("DTD.declarationValidity accepts a well-formed declaration set")
    func test_dtdDeclarationValidity_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY><!ATTLIST r id CDATA #IMPLIED>]><r/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.declarationValidity).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.rootElementType requires the root to match the DOCTYPE name")
    func test_dtdRootElementType() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE expected [<!ELEMENT expected EMPTY><!ELEMENT other EMPTY>]>\n<other/>")
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.rootElementType).errors(for: node, in: schema)
        #expect(errors.contains { $0.reason.contains("does not match the DOCTYPE name") })
    }

    @Test("DTD.rootElementType accepts a matching root element name")
    func test_dtdRootElementType_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE expected [<!ELEMENT expected EMPTY>]>\n<expected/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.rootElementType).errors(for: node, in: schema).isEmpty)
    }

    @Test("DTD.standaloneAttributes rejects an externally-declared default in standalone documents")
    func test_dtdStandaloneAttributes() throws {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root/>"
        let (node, schema) = try ValidationRuleTestSupport.dtd(xml, resolver: ValidationRuleTestSupport.standaloneResolver())
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.standaloneAttributes).errors(for: node, in: schema)
        #expect(errors.contains { $0.reason.contains("externally-declared default") })
    }

    @Test("DTD.standaloneAttributes accepts internally-declared attributes in standalone documents")
    func test_dtdStandaloneAttributes_succeeds() throws {
        let xml = """
        <?xml version='1.0' standalone='yes'?>
        <!DOCTYPE root SYSTEM "x.dtd" [<!ATTLIST root token (a|b|c) "a">]>
        <root token="b" id="ok"/>
        """
        let (node, schema) = try ValidationRuleTestSupport.dtd(xml, resolver: ValidationRuleTestSupport.standaloneResolver())
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.standaloneAttributes).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.standaloneElementWhitespace rejects whitespace in externally-declared mixed content")
    func test_dtdStandaloneElementWhitespace() throws {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\">\n  <child>x</child>\n</root>"
        let (node, schema) = try ValidationRuleTestSupport.dtd(xml, resolver: ValidationRuleTestSupport.standaloneResolver())
        let errors = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.standaloneElementWhitespace).errors(
            for: node,
            in: schema,
        )
        #expect(errors.contains { $0.reason.contains("whitespace in the externally-declared element content") })
    }

    @Test("DTD.standaloneElementWhitespace accepts compact content in standalone documents")
    func test_dtdStandaloneElementWhitespace_succeeds() throws {
        let xml = "<?xml version='1.0' standalone='yes'?>\n<!DOCTYPE root SYSTEM \"x.dtd\">\n<root token=\"b\" id=\"ok\"><child>x</child></root>"
        let (node, schema) = try ValidationRuleTestSupport.dtd(xml, resolver: ValidationRuleTestSupport.standaloneResolver())
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.standaloneElementWhitespace).errors(for: node, in: schema)
            .isEmpty)
    }

    @Test("DTD.parseAdvisories surfaces parse-time advisories at the document root")
    func test_dtdParseAdvisories() throws {
        let loose = """
        <!DOCTYPE root [
        <!ELEMENT root (#PCDATA)>
        <!ENTITY % outside SYSTEM "x.ent">
        %outside;
        %undeclared;
        ]>
        <root/>
        """
        let (node, schema) = try ValidationRuleTestSupport.dtd(loose, resolver: ValidationRuleTestSupport.standaloneResolver())
        let warnings = PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank
            .validating(PureXML.Validation.DTD.parseAdvisories)
            .warnings(for: node, in: schema)
        #expect(warnings.contains { $0.reason.contains("'%undeclared;' is referenced but not declared") })
    }

    @Test("DTD.parseAdvisories stays quiet when there are no advisories")
    func test_dtdParseAdvisories_succeeds() throws {
        let (node, schema) = try ValidationRuleTestSupport.dtd("<!DOCTYPE r [<!ELEMENT r EMPTY>]><r/>")
        #expect(PureXML.Validation.Validator<ValidationRuleTestSupport.DTDSchema>.blank.validating(PureXML.Validation.DTD.parseAdvisories).warnings(for: node, in: schema).isEmpty)
    }
}
