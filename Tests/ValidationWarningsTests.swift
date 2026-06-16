@testable import PureXML
import Testing

/// Tests for the validation-rules.md warnings channel: advisory findings are
/// collected separately from errors and promoted only under `strict: true`.
@Suite("Validation warnings channel")
struct ValidationWarningsTests {
    private struct WarningLeaf: PureXML.Validation.Validatable, PureXML.Validation.HasWarnings {
        let message: String

        func validationWarnings(at path: [PureXML.Validation.PathKey]) -> [PureXML.Validation.ValidationError] {
            [PureXML.Validation.ValidationError(reason: message, at: path, severity: .warning)]
        }
    }

    private func advisoryRule() -> PureXML.Validation.Validation<PureXML.Model.Element, Void> {
        PureXML.Validation.Validation(
            description: "advisory only",
            check: { context in
                [PureXML.Validation.ValidationError(reason: "note", at: context.codingPath, severity: .warning)]
            },
        )
    }

    @Test("HasWarnings supplies advisory findings at the coding path")
    func test_hasWarningsAtPath() {
        let leaf = WarningLeaf(message: "advisory")
        let warnings = leaf.validationWarnings(at: [.element("a")])
        #expect(warnings.count == 1)
        #expect(warnings.first?.reason == "advisory")
        #expect(warnings.first?.codingPath.map(\.stringValue) == ["a"])
    }

    @Test("strict validation throws warnings; lenient validation returns them")
    func test_strictPromotesWarnings() throws {
        let node = PureXML.Model.Node.document([.element(.init("a"))])
        let validator = PureXML.Validation.Validator<Void>.blank.validating(advisoryRule())

        #expect(throws: PureXML.Validation.ValidationErrorCollection.self) {
            try validator.validate(node, in: (), strict: true)
        }
        #expect(throws: Never.self) {
            try validator.validate(node, in: (), strict: false)
        }

        let lenient = validator.outcome(for: node, in: (), strict: false)
        #expect(lenient.errors.isEmpty)
        #expect(lenient.warnings.count == 1)
        #expect(!lenient.isValid)

        let promoted = validator.outcome(for: node, in: (), strict: true)
        #expect(promoted.errors.count == 1)
        #expect(promoted.warnings.isEmpty)
        #expect(!promoted.isValid)
    }

    @Test("Rule-produced warning severity is split from errors")
    func test_ruleSeveritySplit() {
        let node = PureXML.Model.Node.document([.element(.init("a"))])
        let validator = PureXML.Validation.Validator<Void>.blank.validating(advisoryRule())
        #expect(validator.errors(for: node, in: ()).isEmpty)
        #expect(validator.warnings(for: node, in: ()).count == 1)
        #expect(validator.findings(for: node, in: ()).count == 1)
    }

    @Test("DTD parse advisories promote under strict validation")
    func test_dtdParseAdvisoriesStrict() throws {
        let xml = "<!DOCTYPE r SYSTEM \"x.dtd\" [<!ELEMENT r ANY>]>\n<r>&mystery;</r>"
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(
            xml,
            limits: .init(allowDoctype: true),
            resolver: .refusing,
        )
        let schema = PureXML.Validation.DTDSchema(parsed.documentType)
        let validator = PureXML.Validation.DTD.validator(strict: false)
        #expect(validator.warnings(for: parsed.node, in: schema).contains { $0.reason.contains("'&mystery;' is referenced but not declared") })
        #expect(throws: PureXML.Validation.ValidationErrorCollection.self) {
            try validator.validate(parsed.node, in: schema, strict: true)
        }
        #expect(throws: Never.self) {
            try validator.validate(parsed.node, in: schema, strict: false)
        }
    }

    @Test("Schematron reports stay warnings until strict validation")
    func test_schematronWarningsSplit() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="book">
              <report test="count(author) &gt; 2">more than two authors</report>
            </rule>
          </pattern>
        </schema>
        """
        let xml = """
        <book>
          <author>A</author><author>B</author><author>C</author>
        </book>
        """
        let node = try PureXML.parse(xml)
        let parsed = try PureXML.Validation.SchematronParser.parse(schema)
        let validation = PureXML.Validation.Schematron.rule(
            parsed.patterns,
            schemaLets: parsed.lets,
            diagnostics: parsed.diagnostics,
        )
        let validator = PureXML.Validation.Validator<Void>.blank.validating(validation)
        #expect(validator.errors(for: node, in: ()).isEmpty)
        #expect(validator.warnings(for: node, in: ()).count == 1)
        #expect(throws: PureXML.Validation.ValidationErrorCollection.self) {
            try validator.validate(node, in: (), strict: true)
        }
        #expect(throws: Never.self) {
            try validator.validate(node, in: (), strict: false)
        }
    }
}
