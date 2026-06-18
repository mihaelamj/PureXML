import Testing
@testable import PureXML

@Suite("HTML5 adoption agency (misnested formatting elements)")
struct HTMLAdoptionTests {
    private func body(_ html: String) -> String {
        let full = PureXML.HTML.serialize(PureXML.HTML.parseDocument(html))
        let wrapper = "<html><head></head><body>"
        guard full.hasPrefix(wrapper), full.hasSuffix("</body></html>") else { return full }
        return String(full.dropFirst(wrapper.count).dropLast("</body></html>".count))
    }

    @Test("Overlapping formatting tags are nested")
    func test_overlapping() {
        #expect(body("<b><i></b></i>") == "<b><i></i></b>")
    }

    @Test("Content after a misnested close is re-wrapped (reconstruction)")
    func test_reconstruction() {
        #expect(body("<b><i></b>X</i>") == "<b><i></i></b><i>X</i>")
    }

    @Test("The fragment parser also reconstructs active formatting elements (#109)")
    func test_fragmentReconstruction() {
        // HTML.parse (fragment) now agrees with the document parser on
        // active-formatting reconstruction, not just the simple overlap case.
        #expect(PureXML.HTML.serialize(PureXML.HTML.parse("<b><i></b>X</i>")) == "<b><i></i></b><i>X</i>")
        #expect(PureXML.HTML.serialize(PureXML.HTML.parse("<p>1<b>2<i>3</b>4</i>5</p>")) == "<p>1<b>2<i>3</i></b><i>4</i>5</p>")
    }

    @Test("A block inside a formatting element triggers the furthest-block path")
    func test_furthestBlock() {
        #expect(body("<b>1<p>2</b>3</p>") == "<b>1</b><p><b>2</b>3</p>")
    }

    @Test("Nested anchors and formatting close cleanly")
    func test_nestedFormatting() {
        #expect(body("<a><b></a>") == "<a><b></b></a>")
    }

    @Test("The canonical adoption-agency example reparents correctly")
    func test_canonicalExample() {
        // The well-known html5lib case for the adoption agency algorithm.
        #expect(body("<p>1<b>2<i>3</b>4</i>5</p>") == "<p>1<b>2<i>3</i></b><i>4</i>5</p>")
    }

    @Test("Well-nested formatting is unchanged")
    func test_wellNested() {
        #expect(body("<b><i>x</i></b>") == "<b><i>x</i></b>")
        #expect(body("<p><b>bold</b> and <i>italic</i></p>") == "<p><b>bold</b> and <i>italic</i></p>")
    }
}
