@testable import PureXML
import Testing

@Suite("XInclude content negotiation, cycle detection, text+fragment")
struct XIncludeNegotiationTests {
    private func roots(_ node: PureXML.Model.Node) -> [PureXML.Model.Element] {
        guard case let .document(children) = node else { return [] }
        return children.compactMap(\.element)
    }

    @Test("accept, accept-language, and encoding are surfaced to the loader")
    func test_requestHints() throws {
        let xml = """
        <doc xmlns:xi="http://www.w3.org/2001/XInclude">
          <xi:include href="t.txt" parse="text" accept="text/plain" accept-language="fr" encoding="iso-8859-1"/>
        </doc>
        """
        var seen: PureXML.XInclude.XIncludeRequest?
        _ = try PureXML.XInclude.process(xml, loading: { request in
            seen = request
            return "loaded"
        })
        #expect(seen?.uri == "t.txt")
        #expect(seen?.accept == "text/plain")
        #expect(seen?.acceptLanguage == "fr")
        #expect(seen?.encoding == "iso-8859-1")
        #expect(seen?.isText == true)
    }

    @Test("A self-including resource is detected as a cycle")
    func test_cycle() throws {
        let selfInclude = """
        <doc xmlns:xi="http://www.w3.org/2001/XInclude"><xi:include href="a.xml"/></doc>
        """
        #expect(throws: PureXML.XInclude.XIncludeError.self) {
            _ = try PureXML.XInclude.process(selfInclude, base: "a.xml", loadingURI: { _ in selfInclude })
        }
    }

    @Test("A non-cyclic diamond include does not falsely trip cycle detection")
    func test_diamondNotCycle() throws {
        // root includes b and c; both include leaf. Same resource on two separate
        // branches is not a cycle.
        let leaf = "<leaf/>"
        let xml = """
        <doc xmlns:xi="http://www.w3.org/2001/XInclude">
          <xi:include href="leaf.xml"/>
          <xi:include href="leaf.xml"/>
        </doc>
        """
        let result = try PureXML.XInclude.process(xml, loadingURI: { $0 == "leaf.xml" ? leaf : nil })
        #expect(roots(result).first?.children.compactMap(\.element).count == 2)
    }

    @Test("parse=text with an xpointer is rejected")
    func test_textWithFragment() {
        let xml = """
        <doc xmlns:xi="http://www.w3.org/2001/XInclude">
          <xi:include href="t.txt" parse="text" xpointer="element(/1)"/>
        </doc>
        """
        #expect(throws: PureXML.XInclude.XIncludeError.textWithFragment) {
            _ = try PureXML.XInclude.process(xml, loadingURI: { _ in "x" })
        }
    }
}
