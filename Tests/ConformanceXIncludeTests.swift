@testable import PureXML
import Testing

/// XInclude and XPointer conformance, driven through the validation framework
/// (Tier 2): inclusion semantics, fallback, fragment selection, and the
/// XPointer schemes against their spec outcomes.
@Suite("Conformance corpus: XInclude and XPointer")
struct ConformanceXIncludeTests {
    private let xiNamespace = "xmlns:xi=\"http://www.w3.org/2001/XInclude\""

    private func included(_ xml: String, _ documents: [String: String]) throws -> String {
        let node = try PureXML.XInclude.process(xml, base: "http://example.com/doc.xml", loadingURI: { documents[$0] })
        return PureXML.serialize(node, options: .compact)
    }

    private func pointed(_ pointer: String, over xml: String) throws -> String {
        try PureXML.XPointer.evaluate(pointer, over: PureXML.parse(xml)).map(\.stringValue).joined(separator: "|")
    }

    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        var cases: [PureXML.Validation.ConformanceCase] = []
        func add(_ name: String, _ actual: String, _ expected: String) {
            cases.append(.init(name: name, actual: actual, expected: expected))
        }
        // XInclude: substitution, text inclusion, fallback, fragment selection.
        try add(
            "include-xml-substitutes",
            included("<doc \(xiNamespace)><xi:include href=\"f.xml\"/></doc>", ["http://example.com/f.xml": "<x>hi</x>"]),
            "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><x>hi</x></doc>",
        )
        try add(
            "include-text-escapes",
            included("<doc \(xiNamespace)><xi:include href=\"f.txt\" parse=\"text\"/></doc>", ["http://example.com/f.txt": "a<b&c"]),
            "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">a&lt;b&amp;c</doc>",
        )
        try add(
            "fallback-on-missing",
            included("<doc \(xiNamespace)><xi:include href=\"missing.xml\"><xi:fallback>none</xi:fallback></xi:include></doc>", [:]),
            "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">none</doc>",
        )
        try add(
            "relative-href-resolves",
            included("<doc \(xiNamespace)><xi:include href=\"sub/f.xml\"/></doc>", ["http://example.com/sub/f.xml": "<y/>"]),
            "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><y/></doc>",
        )
        // XPointer schemes over a fixed document.
        let book = "<book><chapter id=\"intro\"><para>first</para><para>second</para></chapter>"
            + "<chapter id=\"main\"><para>third</para></chapter></book>"
        try add("shorthand-id", pointed("intro", over: book), "firstsecond")
        try add("element-from-id", pointed("element(intro/2)", over: book), "second")
        try add("element-from-root", pointed("element(/1/2)", over: book), "third")
        // //para[1] binds the predicate per step: every para first in its parent
        // (both chapters), the classic XPath semantic.
        try add("xpointer-xpath-per-step-predicate", pointed("xpointer(//para[1])", over: book), "first|third")
        try add("xpointer-xpath-document-first", pointed("xpointer((//para)[1])", over: book), "first")
        try add("xpointer-count-attribute", pointed("xpointer(//chapter[@id='main']/para)", over: book), "third")
        return cases
    }

    @Test("The XInclude/XPointer conformance corpus passes with no located failures")
    func test_xincludeCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
