@testable import PureXML
import Testing

@Suite("XInclude")
struct XIncludeTests {
    // MARK: URI resolution

    @Test("Relative references resolve against a base per RFC 3986")
    func test_uriResolution() {
        let resolve = PureXML.XInclude.URIReference.resolve
        #expect(resolve("g", "http://a/b/c/d") == "http://a/b/c/g")
        #expect(resolve("../g", "http://a/b/c/d") == "http://a/b/g")
        #expect(resolve("../../g", "http://a/b/c/d") == "http://a/g")
        #expect(resolve("/g", "http://a/b/c/d") == "http://a/g")
        #expect(resolve("http://x/y", "http://a/b/c/d") == "http://x/y")
        #expect(resolve("./g", "http://a/b/c/d") == "http://a/b/c/g")
    }

    // MARK: Processing

    private func process(_ xml: String, _ load: @escaping (String) -> String?) throws -> String {
        let node = try PureXML.XInclude.process(xml, base: "http://example.com/doc.xml", loadingURI: load)
        return PureXML.serialize(node, options: .compact)
    }

    @Test("xi:include parse=xml substitutes the document element")
    func test_includeXML() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><xi:include href=\"frag.xml\"/></doc>"
        let result = try process(xml) { uri in
            uri == "http://example.com/frag.xml" ? "<inserted>hi</inserted>" : nil
        }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><inserted>hi</inserted></doc>")
    }

    @Test("xi:include parse=text substitutes raw text")
    func test_includeText() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
            + "<xi:include href=\"note.txt\" parse=\"text\"/></doc>"
        let result = try process(xml) { _ in "a < b" }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">a &lt; b</doc>")
    }

    @Test("xi:include with an xpointer selects a fragment")
    func test_includeWithXPointer() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
            + "<xi:include href=\"frag.xml\" xpointer=\"xpointer(//item[2])\"/></doc>"
        let result = try process(xml) { _ in "<list><item>one</item><item>two</item></list>" }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><item>two</item></doc>")
    }

    @Test("xi:include with an xpointer range() includes the covering range")
    func test_includeRange() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
            + "<xi:include href=\"frag.xml\" xpointer=\"xpointer(range(//item[2]))\"/></doc>"
        let result = try process(xml) { _ in "<list><item>one</item><item>two</item></list>" }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><item>two</item></doc>")
    }

    @Test("xi:include with a string-range xpointer includes the matched text")
    func test_includeStringRange() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
            + "<xi:include href=\"frag.xml\" xpointer=\"xpointer(string-range(//item, 'wo'))\"/></doc>"
        let result = try process(xml) { _ in "<list><item>one</item><item>two</item></list>" }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">wo</doc>")
    }

    @Test("href resolves against an xml:base on an ancestor")
    func test_xmlBase() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\" xml:base=\"sub/\">"
            + "<xi:include href=\"frag.xml\"/></doc>"
        var requested = ""
        let result = try process(xml) { uri in
            requested = uri
            return "<ok/>"
        }
        #expect(requested == "http://example.com/sub/frag.xml")
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\" xml:base=\"sub/\"><ok/></doc>")
    }

    @Test("A failed include uses its xi:fallback")
    func test_fallback() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\">"
            + "<xi:include href=\"missing.xml\"><xi:fallback><backup/></xi:fallback></xi:include></doc>"
        let result = try process(xml) { _ in nil }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><backup/></doc>")
    }

    @Test("A failed include with no fallback throws")
    func test_unresolved() {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><xi:include href=\"missing.xml\"/></doc>"
        #expect(throws: PureXML.XInclude.XIncludeError.self) {
            _ = try PureXML.XInclude.process(xml, loadingURI: { _ in nil })
        }
    }

    @Test("Includes nest: an included document's own includes resolve")
    func test_nestedInclude() throws {
        let xml = "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><xi:include href=\"a.xml\"/></doc>"
        let result = try process(xml) { uri in
            switch uri {
            case "http://example.com/a.xml":
                "<a xmlns:xi=\"http://www.w3.org/2001/XInclude\"><xi:include href=\"b.xml\"/></a>"
            case "http://example.com/b.xml":
                "<b/>"
            default:
                nil
            }
        }
        #expect(result == "<doc xmlns:xi=\"http://www.w3.org/2001/XInclude\"><a xmlns:xi=\"http://www.w3.org/2001/XInclude\"><b/></a></doc>")
    }
}
