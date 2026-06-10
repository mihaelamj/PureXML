@testable import PureXML
import Testing

/// HTML5 depth conformance, driven through the validation framework (#119, the
/// zone that produced #109): the spec-fidelity cases go through the document
/// parser; the lenient-model cases through the fragment parser.
@Suite("Conformance corpus: HTML depth")
struct ConformanceHTMLDepthTests {
    /// The serialized body content of a full document parse.
    private func documentBody(_ html: String) -> String {
        let full = PureXML.HTML.serialize(PureXML.HTML.parseDocument(html))
        let wrapper = "<html><head></head><body>"
        guard full.hasPrefix(wrapper), full.hasSuffix("</body></html>") else { return full }
        return String(full.dropFirst(wrapper.count).dropLast("</body></html>".count))
    }

    private func fragment(_ html: String) -> String {
        PureXML.HTML.serialize(PureXML.HTML.parse(html))
    }

    private func corpus() -> [PureXML.Validation.ConformanceCase] {
        var cases: [PureXML.Validation.ConformanceCase] = []
        func document(_ name: String, _ input: String, _ expected: String) {
            cases.append(.init(name: name, actual: documentBody(input), expected: expected))
        }
        func lenient(_ name: String, _ input: String, _ expected: String) {
            cases.append(.init(name: name, actual: fragment(input), expected: expected))
        }
        // The adoption agency's furthest-block path and the deep misnesting case.
        document("adoption-furthest-block", "<b>1<p>2</b>3</p>", "<b>1</b><p><b>2</b>3</p>")
        document("adoption-deep-misnesting", "<p>1<b>2<i>3</b>4</i>5</p>", "<p>1<b>2<i>3</i></b><i>4</i>5</p>")
        // Foster parenting: stray table content surfaces before the table, and
        // the tr gets its implied tbody (both per the HTML5 algorithm).
        document("foster-parented-text", "<table>x<tr><td>a</td></tr></table>", "x<table><tbody><tr><td>a</td></tr></tbody></table>")
        // template keeps its flow content nested.
        document("template-content-nested", "<template><div>x</div></template>", "<template><div>x</div></template>")
        // Lenient fragment model: raw-text elements, implied closes.
        lenient("raw-text-script", "<script>if(a<b)x()</script>", "<script>if(a<b)x()</script>")
        lenient("implied-dt-dd-close", "<dl><dt>t<dd>d</dl>", "<dl><dt>t</dt><dd>d</dd></dl>")
        lenient("implied-cell-close", "<table><tr><td>a<td>b</table>", "<table><tr><td>a</td><td>b</td></tr></table>")
        lenient("comment-kept-in-flow", "<div><!-- note -->x</div>", "<div><!-- note -->x</div>")
        return cases
    }

    @Test("The HTML depth corpus passes with no located failures")
    func test_htmlDepthCorpusConforms() {
        let failures = PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
