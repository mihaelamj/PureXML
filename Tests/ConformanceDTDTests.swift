@testable import PureXML
import Testing

/// DTD content-model conformance, driven through the validation framework (its
/// own suite to keep the main corpus under the cap).
@Suite("Conformance corpus: DTD content models")
struct ConformanceDTDTests {
    private struct DTDSpec {
        let name: String
        let model: String
        let xml: String
        let valid: Bool
    }

    /// Sequences, choices, occurrence indicators, mixed, EMPTY, and ANY content
    /// models, validated against the verdict the XML 1.0 DTD rules prescribe.
    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            DTDSpec(name: "sequence-ok", model: "(b,c)", xml: "<a><b/><c/></a>", valid: true),
            DTDSpec(name: "sequence-wrong-order", model: "(b,c)", xml: "<a><c/><b/></a>", valid: false),
            DTDSpec(name: "sequence-missing", model: "(b,c)", xml: "<a><b/></a>", valid: false),
            DTDSpec(name: "choice-ok", model: "(b|c)", xml: "<a><c/></a>", valid: true),
            DTDSpec(name: "choice-both-rejected", model: "(b|c)", xml: "<a><b/><c/></a>", valid: false),
            DTDSpec(name: "star-empty", model: "(b)*", xml: "<a></a>", valid: true),
            DTDSpec(name: "star-many", model: "(b)*", xml: "<a><b/><b/></a>", valid: true),
            DTDSpec(name: "plus-requires-one", model: "(b)+", xml: "<a></a>", valid: false),
            DTDSpec(name: "optional-too-many", model: "(b)?", xml: "<a><b/><b/></a>", valid: false),
            DTDSpec(name: "pcdata-text", model: "(#PCDATA)", xml: "<a>t</a>", valid: true),
            DTDSpec(name: "pcdata-rejects-child", model: "(#PCDATA)", xml: "<a><b/></a>", valid: false),
            DTDSpec(name: "mixed-content", model: "(#PCDATA|b)*", xml: "<a>t<b/>u</a>", valid: true),
            DTDSpec(name: "empty-rejects-content", model: "EMPTY", xml: "<a>x</a>", valid: false),
            DTDSpec(name: "any-allows-anything", model: "ANY", xml: "<a><b/>x</a>", valid: true),
        ]
        return try specs.map { spec in
            let dtd = "<!ELEMENT a \(spec.model)><!ELEMENT b EMPTY><!ELEMENT c EMPTY>"
            let doc = "<!DOCTYPE a [\(dtd)]>\(spec.xml)"
            let errors = try PureXML.validateAgainstInternalDTD(doc)
            return PureXML.Validation.ConformanceCase(
                name: spec.name,
                actual: errors.isEmpty ? "valid" : "invalid",
                expected: spec.valid ? "valid" : "invalid",
            )
        }
    }

    @Test("The DTD content-model conformance corpus passes with no located failures")
    func test_dtdCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
