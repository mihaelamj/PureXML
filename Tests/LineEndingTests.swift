@testable import PureXML
import Testing

@Suite("Line-ending normalization and XML 1.1")
struct LineEndingTests {
    private func rootText(_ xml: String) throws -> String {
        let node = try PureXML.parse(xml)
        guard case let .document(children) = node, let root = children.compactMap(\.element).first else {
            return ""
        }
        return root.children.reduce(into: "") { result, child in
            if case let .text(text) = child { result += text }
        }
    }

    @Test("CRLF is normalized to a single line feed")
    func test_crlf() throws {
        #expect(try rootText("<a>x\r\ny</a>") == "x\ny")
    }

    @Test("A lone carriage return is normalized to a line feed")
    func test_loneCR() throws {
        #expect(try rootText("<a>x\ry</a>") == "x\ny")
    }

    @Test("In XML 1.0, NEL is preserved as data")
    func test_nel10() throws {
        #expect(try rootText("<a>x\u{85}y</a>") == "x\u{85}y")
    }

    @Test("In XML 1.1, NEL is normalized to a line feed")
    func test_nel11() throws {
        #expect(try rootText("<?xml version=\"1.1\"?><a>x\u{85}y</a>") == "x\ny")
    }

    @Test("In XML 1.1, LINE SEPARATOR is normalized to a line feed")
    func test_lineSeparator11() throws {
        #expect(try rootText("<?xml version=\"1.1\"?><a>x\u{2028}y</a>") == "x\ny")
    }

    @Test("In XML 1.1, CR followed by NEL collapses to one line feed")
    func test_crNel11() throws {
        #expect(try rootText("<?xml version=\"1.1\"?><a>x\r\u{85}y</a>") == "x\ny")
    }

    @Test("In XML 1.0, LINE SEPARATOR is preserved as data")
    func test_lineSeparator10() throws {
        #expect(try rootText("<a>x\u{2028}y</a>") == "x\u{2028}y")
    }
}
