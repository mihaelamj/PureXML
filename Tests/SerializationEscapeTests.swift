@testable import PureXML
import Testing

@Suite("Serialization: CDATA-as-text and ASCII-only")
struct SerializationEscapeTests {
    private func serialize(_ node: PureXML.Model.Node, _ options: PureXML.Emitting.Options) -> String {
        PureXML.serialize(node, options: options)
    }

    @Test("cdataAsText emits a CDATA section as escaped text")
    func test_cdataAsText() {
        let element = PureXML.Model.Element("a", children: [.cdata("x < y & z")])
        let asSection = serialize(.element(element), PureXML.Emitting.Options(prettyPrint: false))
        #expect(asSection == "<a><![CDATA[x < y & z]]></a>")
        let asText = serialize(.element(element), PureXML.Emitting.Options(prettyPrint: false, cdataAsText: true))
        #expect(asText == "<a>x &lt; y &amp; z</a>")
    }

    @Test("asciiOnly escapes non-ASCII characters as numeric references")
    func test_asciiOnlyText() {
        let element = PureXML.Model.Element("a", children: [.text("café")])
        let options = PureXML.Emitting.Options(prettyPrint: false, asciiOnly: true)
        #expect(serialize(.element(element), options) == "<a>caf&#xE9;</a>")
    }

    @Test("asciiOnly escapes non-ASCII in attribute values too")
    func test_asciiOnlyAttribute() {
        let element = PureXML.Model.Element("a", attributes: [.init("t", "ñ")])
        let options = PureXML.Emitting.Options(prettyPrint: false, asciiOnly: true)
        #expect(serialize(.element(element), options) == "<a t=\"&#xF1;\"/>")
    }

    @Test("Without asciiOnly, non-ASCII is left verbatim")
    func test_nonAsciiVerbatim() {
        let element = PureXML.Model.Element("a", children: [.text("café")])
        #expect(serialize(.element(element), PureXML.Emitting.Options(prettyPrint: false)) == "<a>café</a>")
    }

    @Test("textEscaping .standard leaves a carriage return verbatim")
    func test_standardKeepsCarriageReturn() {
        let element = PureXML.Model.Element("a", children: [.text("x\ry")])
        #expect(serialize(.element(element), PureXML.Emitting.Options(prettyPrint: false)) == "<a>x\ry</a>")
    }

    @Test("textEscaping .roundTrip escapes a carriage return so it survives a parse")
    func test_roundTripEscapesCarriageReturn() throws {
        let element = PureXML.Model.Element("a", children: [.text("x\ry")])
        let options = PureXML.Emitting.Options(prettyPrint: false, textEscaping: .roundTrip)
        let serialized = serialize(.element(element), options)
        #expect(serialized == "<a>x&#xD;y</a>")
        // The escaped form survives end-of-line normalization; the verbatim form does not.
        #expect(try PureXML.parse(serialized) == .document([.element(element)]))
        let lossy = serialize(.element(element), PureXML.Emitting.Options(prettyPrint: false))
        #expect(try PureXML.parse(lossy) == .document([.element(.init("a", children: [.text("x\ny")]))]))
    }
}
