@testable import PureXML
import Testing

@Suite("XPointer")
struct XPointerTests {
    private func doc() throws -> PureXML.Model.Node {
        try PureXML.parse(
            "<book>"
                + "<chapter id=\"intro\"><para>first</para><para>second</para></chapter>"
                + "<chapter id=\"main\"><para>third</para></chapter>"
                + "</book>",
        )
    }

    private func strings(_ pointer: String) throws -> [String] {
        try PureXML.XPointer.evaluate(pointer, over: doc()).map(\.stringValue)
    }

    @Test("A shorthand pointer resolves an id")
    func test_shorthand() throws {
        #expect(try strings("intro") == ["firstsecond"])
    }

    @Test("element() navigates child positions from an id")
    func test_elementFromId() throws {
        #expect(try strings("element(intro/2)") == ["second"])
        #expect(try strings("element(intro/1)") == ["first"])
    }

    @Test("element() navigates from the document root")
    func test_elementFromRoot() throws {
        #expect(try strings("element(/1/2)") == ["third"])
        #expect(try strings("element(/1)") == ["firstsecondthird"])
    }

    @Test("xpointer() evaluates a full XPath expression")
    func test_xpointerScheme() throws {
        #expect(try strings("xpointer(//para[2])") == ["second"])
        #expect(try strings("xpointer(//chapter[@id='main']/para)") == ["third"])
    }

    @Test("Scheme parts fall back to the first non-empty result")
    func test_fallback() throws {
        // The first part selects nothing (no such id), so the second part wins.
        #expect(try strings("element(nope/1)element(main/1)") == ["third"])
    }

    @Test("A malformed pointer is rejected")
    func test_malformed() {
        #expect(throws: PureXML.XPointer.XPointerError.self) {
            _ = try PureXML.XPointer.Pointer("xpointer(")
        }
        #expect(throws: PureXML.XPointer.XPointerError.self) {
            _ = try PureXML.XPointer.Pointer("bogus(/1)")
        }
    }

    @Test("An empty pointer is rejected")
    func test_empty() {
        #expect(throws: PureXML.XPointer.XPointerError.empty) {
            _ = try PureXML.XPointer.Pointer("   ")
        }
    }
}
