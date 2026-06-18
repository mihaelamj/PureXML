import Testing
@testable import PureXML

/// Canonical XML exclusive and 2.0 mode conformance, driven through the
/// validation framework (its own suite to keep the main corpus under the cap).
@Suite("Conformance corpus: C14N exclusive and 2.0")
struct ConformanceCanonicalModesTests {
    private struct ModeSpec {
        let name: String
        let input: String
        let options: PureXML.Canonical.Options
        let expected: String
    }

    /// Exclusive C14N renders a namespace only where it is visibly used; Canonical
    /// XML 2.0 trims and drops ignorable whitespace text.
    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            ModeSpec(name: "exclusive-drops-unused-ns", input: "<r xmlns:x=\"urn:x\"><c/></r>", options: .exclusive, expected: "<r><c></c></r>"),
            ModeSpec(name: "exclusive-renders-at-use", input: "<r xmlns:x=\"urn:x\"><x:c/></r>", options: .exclusive, expected: "<r><x:c xmlns:x=\"urn:x\"></x:c></r>"),
            ModeSpec(name: "c2-drops-whitespace-nodes", input: "<r>  <c/>  </r>", options: .canonical2, expected: "<r><c></c></r>"),
            ModeSpec(name: "c2-trims-text", input: "<r>  hi  </r>", options: .canonical2, expected: "<r>hi</r>"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.Canonical.canonicalize(PureXML.parse(spec.input), options: spec.options)
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    @Test("The C14N exclusive/2.0 conformance corpus passes with no located failures")
    func test_canonicalModesCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
