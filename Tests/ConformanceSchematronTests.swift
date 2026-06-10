@testable import PureXML
import Testing

/// Schematron conformance, driven through the validation framework (kept in its
/// own suite so the main corpus stays under the type-body cap).
@Suite("Conformance corpus: Schematron")
struct ConformanceSchematronTests {
    private struct SchematronSpec {
        let name: String
        let rule: String
        let xml: String
        let valid: Bool
    }

    /// An `assert` fires when its test is false, a `report` when its test is true,
    /// and a rule whose context matches nothing is inert.
    private func schematronCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let assertRule = "<rule context=\"a\"><assert test=\"b\">missing b</assert></rule>"
        let ageRule = "<rule context=\"age\"><assert test=\"number(.) &lt; 100\">too high</assert></rule>"
        let reportRule = "<rule context=\"a\"><report test=\"@flag\">flagged</report></rule>"
        let specs = [
            SchematronSpec(name: "assert-satisfied", rule: assertRule, xml: "<a><b/></a>", valid: true),
            SchematronSpec(name: "assert-violated", rule: assertRule, xml: "<a/>", valid: false),
            SchematronSpec(name: "context-no-match-inert", rule: "<rule context=\"z\"><assert test=\"false()\">never</assert></rule>", xml: "<a/>", valid: true),
            SchematronSpec(name: "number-comparison-ok", rule: ageRule, xml: "<age>50</age>", valid: true),
            SchematronSpec(name: "number-comparison-fail", rule: ageRule, xml: "<age>150</age>", valid: false),
            SchematronSpec(name: "report-not-fired", rule: reportRule, xml: "<a/>", valid: true),
            SchematronSpec(name: "report-fired", rule: reportRule, xml: "<a flag=\"1\"/>", valid: false),
        ]
        return try specs.map { spec in
            let schema = "<schema xmlns=\"http://purl.oclc.org/dsdl/schematron\"><pattern>\(spec.rule)</pattern></schema>"
            let errors = try PureXML.Validation.Schematron(schema: schema).validate(spec.xml)
            return PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: errors.isEmpty ? "valid" : "invalid",
                expected: spec.valid ? "valid" : "invalid",
            )
        }
    }

    @Test("The Schematron conformance corpus passes with no located failures")
    func test_schematronCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: schematronCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
