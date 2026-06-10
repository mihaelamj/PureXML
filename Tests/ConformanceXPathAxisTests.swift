@testable import PureXML
import Testing

/// XPath 1.0 axis and predicate conformance, driven through the validation
/// framework (its own suite to keep the main corpus under the cap).
@Suite("Conformance corpus: XPath axes and predicates")
struct ConformanceXPathAxisTests {
    private struct AxisSpec {
        let name: String
        let expression: String
        let expected: String
    }

    /// Axis navigation and positional predicates over a fixed tree, checked
    /// against the node-set the XPath 1.0 spec selects (coerced to a string).
    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        let document = try PureXML.parse("<root><a id=\"1\"><b>x</b><b>y</b></a><a id=\"2\"><c>z</c></a></root>")
        let specs = [
            AxisSpec(name: "descendant-count", expression: "count(//b)", expected: "2"),
            AxisSpec(name: "all-elements-count", expression: "count(//*)", expected: "6"),
            AxisSpec(name: "positional-predicate", expression: "//b[2]", expected: "y"),
            AxisSpec(name: "last-predicate", expression: "//a[last()]/c", expected: "z"),
            AxisSpec(name: "ancestor-axis", expression: "count(//c/ancestor::a)", expected: "1"),
            AxisSpec(name: "ancestor-or-self", expression: "count(//c/ancestor-or-self::*)", expected: "3"),
            AxisSpec(name: "following-sibling", expression: "count(//a[1]/following-sibling::a)", expected: "1"),
            AxisSpec(name: "preceding-sibling", expression: "count(//a[2]/preceding-sibling::a)", expected: "1"),
            AxisSpec(name: "attribute-axis", expression: "//a[2]/@id", expected: "2"),
            AxisSpec(name: "attribute-predicate", expression: "count(//a[@id='1'])", expected: "1"),
            AxisSpec(name: "union", expression: "count(//b | //c)", expected: "3"),
            AxisSpec(name: "parent-abbreviation", expression: "//c/../@id", expected: "2"),
            AxisSpec(name: "position-function", expression: "count(//a[position()=1])", expected: "1"),
        ]
        return try specs.map { spec in
            let actual = try PureXML.XPath.Query(spec.expression).string(over: document)
            return PureXML.Validation.ConformanceCase(name: spec.name, actual: actual, expected: spec.expected)
        }
    }

    @Test("The XPath axes/predicates conformance corpus passes with no located failures")
    func test_axisCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
