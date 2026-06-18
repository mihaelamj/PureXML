import Testing
@testable import PureXML

@Suite("HTML5 frameset documents")
struct HTMLFramesetTests {
    private func document(_ html: String) -> String {
        PureXML.HTML.serialize(PureXML.HTML.parseDocument(html))
    }

    @Test("A frameset element replaces the body and frames are void")
    func test_framesetReplacesBody() {
        let html = "<frameset cols=50%,50%><frame src=a><frame src=b></frameset>"
        let expected = "<html><head></head><frameset cols=\"50%,50%\"><frame src=\"a\"><frame src=\"b\"></frameset></html>"
        #expect(document(html) == expected)
    }

    @Test("Nested framesets nest correctly")
    func test_nestedFrameset() {
        let html = "<frameset><frameset><frame></frameset></frameset>"
        let expected = "<html><head></head><frameset><frameset><frame></frameset></frameset></html>"
        #expect(document(html) == expected)
    }

    @Test("A frameset after a head keeps head content")
    func test_framesetWithHead() {
        let html = "<head><title>T</title></head><frameset><frame></frameset>"
        let expected = "<html><head><title>T</title></head><frameset><frame></frameset></html>"
        #expect(document(html) == expected)
    }

    @Test("An ordinary document still produces a body")
    func test_ordinaryStillHasBody() {
        #expect(document("<p>x</p>") == "<html><head></head><body><p>x</p></body></html>")
    }
}
