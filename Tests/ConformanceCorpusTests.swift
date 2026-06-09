@testable import PureXML
import Testing

/// A first Tier-2 conformance corpus, driven through the validation framework:
/// each case runs a PureXML subsystem and the `Conformance` validation rule
/// reports any divergence from the spec-authoritative expected output.
@Suite("Conformance corpus (validation-driven)")
struct ConformanceCorpusTests {
    private struct Spec {
        let name: String
        let input: String
        let expected: String
    }

    /// Canonical XML 1.0 (inclusive, no comments) conformance points, with the
    /// expected canonical form taken from the specification's rules.
    private func canonicalCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let specs = [
            Spec(name: "attribute-ordering", input: "<e b=\"2\" a=\"1\"></e>", expected: "<e a=\"1\" b=\"2\"></e>"),
            Spec(name: "empty-element-expanded", input: "<e/>", expected: "<e></e>"),
            Spec(name: "comments-removed", input: "<e><!--c-->x</e>", expected: "<e>x</e>"),
            Spec(name: "cdata-becomes-escaped-text", input: "<e><![CDATA[<x>&]]></e>", expected: "<e>&lt;x&gt;&amp;</e>"),
            Spec(name: "processing-instruction", input: "<e><?pi data?></e>", expected: "<e><?pi data?></e>"),
            Spec(name: "namespace-rendered", input: "<e xmlns=\"urn:x\"></e>", expected: "<e xmlns=\"urn:x\"></e>"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.Canonical.canonicalize(PureXML.parse(spec.input))
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    private struct XPathSpec {
        let name: String
        let expression: String
        let expected: String
    }

    /// XPath 1.0 core-function conformance points: the function's result coerced
    /// to a string, against the value the specification mandates.
    private func xpathCorpus() throws -> [PureXML.Validation.ConformanceCase] {
        let document = try PureXML.parse("<r><item/><item/><item/></r>")
        let specs = [
            XPathSpec(name: "concat", expression: "concat('a','b','c')", expected: "abc"),
            XPathSpec(name: "substring-length", expression: "substring('12345',2,3)", expected: "234"),
            XPathSpec(name: "substring-open", expression: "substring('12345',2)", expected: "2345"),
            XPathSpec(name: "string-length", expression: "string-length('hello')", expected: "5"),
            XPathSpec(name: "normalize-space", expression: "normalize-space('  a  b  ')", expected: "a b"),
            XPathSpec(name: "translate", expression: "translate('bar','abc','ABC')", expected: "BAr"),
            XPathSpec(name: "substring-before", expression: "substring-before('a/b','/')", expected: "a"),
            XPathSpec(name: "substring-after", expression: "substring-after('a/b','/')", expected: "b"),
            XPathSpec(name: "contains", expression: "contains('hello','ell')", expected: "true"),
            XPathSpec(name: "starts-with", expression: "starts-with('hello','he')", expected: "true"),
            XPathSpec(name: "round-half-up", expression: "round(2.5)", expected: "3"),
            XPathSpec(name: "floor", expression: "floor(2.9)", expected: "2"),
            XPathSpec(name: "ceiling", expression: "ceiling(2.1)", expected: "3"),
            XPathSpec(name: "count", expression: "count(//item)", expected: "3"),
            XPathSpec(name: "div-by-zero-infinity", expression: "1 div 0", expected: "Infinity"),
            XPathSpec(name: "zero-div-zero-nan", expression: "0 div 0", expected: "NaN"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.XPath.Query(spec.expression).string(over: document)
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    @Test("The C14N conformance corpus passes with no located failures")
    func test_corpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: canonicalCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("The XPath core-function conformance corpus passes with no located failures")
    func test_xpathCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: xpathCorpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }

    @Test("A divergent case is reported as a located conformance failure")
    func test_divergenceReported() {
        let bad = PureXML.Validation.ConformanceCase(name: "wrong", actual: "<a></a>", expected: "<b></b>")
        let failures = PureXML.Validation.Conformance.failures(in: [bad])
        #expect(failures.count == 1)
        #expect(failures.first?.codingPath.map(\.stringValue) == ["wrong"])
        #expect(failures.first?.reason.contains("case 'wrong'") == true)
    }
}
