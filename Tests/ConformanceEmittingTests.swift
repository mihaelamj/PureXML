@testable import PureXML
import Testing

/// Serializer options-matrix conformance, driven through the validation
/// framework: each case pins the exact output of one option against the
/// documented behavior (#119, the previously thin Emitting zone).
@Suite("Conformance corpus: serializer options")
struct ConformanceEmittingTests {
    private let compact = PureXML.Emitting.Options(prettyPrint: false)

    private func emitted(_ xml: String, _ options: PureXML.Emitting.Options) throws -> String {
        try PureXML.serialize(PureXML.parse(xml), options: options)
    }

    private func corpus() throws -> [PureXML.Validation.ConformanceCase] {
        var cases: [PureXML.Validation.ConformanceCase] = []
        func add(_ name: String, _ actual: String, _ expected: String) {
            cases.append(.init(name: name, actual: actual, expected: expected))
        }
        try add("self-close-default", emitted("<a/>", compact), "<a/>")
        var expanded = compact
        expanded.selfCloseEmptyElements = false
        try add("expanded-empty", emitted("<a/>", expanded), "<a></a>")
        try add("cdata-kept", emitted("<r><![CDATA[a<b]]></r>", compact), "<r><![CDATA[a<b]]></r>")
        var cdataText = compact
        cdataText.cdataAsText = true
        try add("cdata-as-text", emitted("<r><![CDATA[a<b]]></r>", cdataText), "<r>a&lt;b</r>")
        var ascii = compact
        ascii.asciiOnly = true
        try add("ascii-only-hex-ncr", emitted("<r>\u{E9}\u{20AC}</r>", ascii), "<r>&#xE9;&#x20AC;</r>")
        var roundTrip = compact
        roundTrip.textEscaping = .roundTrip
        // A literal carriage return survives serialization as a reference (the
        // parser would otherwise normalize it away); built programmatically since
        // parsing normalizes line endings first.
        let carriage = PureXML.serialize(.element(.init("r", children: [.text("a\rb")])), options: roundTrip)
        add("roundtrip-carriage-return", carriage, "<r>a&#xD;b</r>")
        var declared = compact
        declared.includeXMLDeclaration = true
        declared.standalone = true
        try add("declaration-standalone", emitted("<r/>", declared), "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n<r/>")
        try add("pretty-deep-nesting", emitted("<a><b><c/></b></a>", .default), "<a>\n  <b>\n    <c/>\n  </b>\n</a>\n")
        try add("attribute-escapes", emitted("<a t=\"a&amp;b&lt;c\"/>", compact), "<a t=\"a&amp;b&lt;c\"/>")
        // The byte path: a non-UTF-8 output encoding writes its canonical name in
        // the declaration (pure-ASCII content, so decoding as UTF-8 is faithful).
        let latin = try PureXML.serialize(PureXML.parse("<r>x</r>"), encoding: .latin1, options: compact)
        add("latin1-declaration", String(decoding: latin, as: UTF8.self), "<?xml version=\"1.0\" encoding=\"ISO-8859-1\"?>\n<r>x</r>")
        return cases
    }

    @Test("The serializer options corpus passes with no located failures")
    func test_emittingCorpusConforms() throws {
        let failures = try PureXML.Validation.Conformance.failures(in: corpus())
        #expect(failures.isEmpty, "\(failures.map(\.reason))")
    }
}
