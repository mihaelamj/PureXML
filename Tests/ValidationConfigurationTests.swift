@testable import PureXML
import Testing

/// Configuration-pin tests: every validator variant lists exactly its active rule
/// descriptions, so adding or rewording a rule fails a test before it is accidental.
@Suite("Validation configuration pins")
struct ValidationConfigurationTests {
    @Test("The structural default validator lists its rules")
    func test_structuralDefault() {
        #expect(PureXML.Validation.Validator<Void>().validationDescriptions == [
            "Element attribute names are unique",
        ])
    }

    @Test("The blank validator carries no rules")
    func test_blank() {
        #expect(PureXML.Validation.Validator<Void>.blank.validationDescriptions.isEmpty)
        #expect(PureXML.Validation.Validator<PureXML.Validation.DTDSchema>.blank.validationDescriptions.isEmpty)
    }

    @Test("The lenient DTD validator lists its non-strict rules in order")
    func test_dtdLenient() {
        let validator = PureXML.Validation.DTD.validator(strict: false)
        #expect(validator.nonReferenceValidationDescriptions == [
            "Element content matches its DTD content model",
            "Required DTD attributes are present",
            "#FIXED DTD attributes hold their fixed value",
            "Enumerated DTD attributes hold a listed value",
            "Tokenized DTD attributes match their declared type",
            "NOTATION DTD attributes name a declared notation",
            "The DTD declarations satisfy their validity constraints",
            "The root element matches the DOCTYPE name",
            "Standalone documents do not depend on external attribute declarations",
            "Standalone documents have no whitespace in externally-declared element content",
            "Parse-time DTD advisories are reviewed",
        ])
        #expect(validator.referenceValidationDescriptions == [
            "DTD ID values are unique and IDREFs resolve",
        ])
    }

    @Test("The strict DTD validator appends undeclared element and attribute rules to the reference tier")
    func test_dtdStrict() {
        let validator = PureXML.Validation.DTD.validator(strict: true)
        #expect(validator.referenceValidationDescriptions.suffix(2) == [
            "Element is declared in the DTD",
            "Every attribute is declared in the DTD",
        ])
    }

    @Test("The HTML validator splits local and document-scoped rules across tiers")
    func test_html() {
        let validator = PureXML.Validation.HTML.validator()
        #expect(validator.nonReferenceValidationDescriptions == [
            "Void HTML elements have no content",
            "HTML elements appear inside their required parent",
        ])
        #expect(validator.referenceValidationDescriptions == [
            "HTML id attributes are unique",
        ])
    }

    @Test("The XSD instance validator splits content and identity rules across tiers")
    func test_xsdInstance() {
        let validator = PureXML.Validation.XSD.validator()
        #expect(validator.nonReferenceValidationDescriptions == [
            "The document element is valid against its XSD type",
        ])
        #expect(validator.referenceValidationDescriptions == [
            "XSD identity constraints hold",
        ])
    }

    @Test("The XSD schema-consistency validator lists named-type rules in tier order")
    func test_xsdSchemaConsistency() {
        let validator = PureXML.Validation.XSDSchema.validator()
        #expect(validator.nonReferenceValidationDescriptions == [
            "A type derives from its base only by methods the base permits",
        ])
        #expect(validator.referenceValidationDescriptions == [
            "A restriction's content model accepts a subset of its base's",
        ])
    }

    @Test("The schema compile validators pin their pre and post rule sets")
    func test_schemaCompile() {
        #expect(PureXML.Validation.SchemaCompile.preCompileValidator().validationDescriptions == [
            "Schema component id attributes are valid NCNames and unique",
            "Schema vocabulary elements follow the schema-for-schemas structure",
            "Global schema component names are unique within their symbol spaces",
            "Simple-type final controls are declared consistently",
            "Schema content models are deterministic (UPA)",
            "Type derivation chains contain no cycles",
            "Schema type references contain no cycles",
            "xs:all group references appear only where permitted",
            "Included schemas are chameleon or match the includer targetNamespace",
        ])
        #expect(PureXML.Validation.SchemaCompile.postCompileValidator().validationDescriptions == [
            "Attribute uses are unique and declare at most one ID attribute",
            "ID-typed value constraints are valid",
            "Element value constraints are valid against their declared types",
            "Complex types extending xs:all groups satisfy XSD placement rules",
            "A complexContent extension is consistent with its base type",
            "Attribute restrictions are faithful to their bases",
            "Simple types do not derive from complex types",
            "Simple-type varieties are declared consistently",
            "Notation declarations are valid",
            "Every schema reference resolves to a declared component",
            "Substitution-group members derive correctly from their head",
        ])
    }

    @Test("Every builtin description is unique and pinned")
    func test_builtinRegistry() {
        let descriptions = PureXML.Validation.BuiltinValidation.allDescriptions
        #expect(descriptions.count == Set(descriptions).count)
        #expect(descriptions.count == 24)
    }
}
