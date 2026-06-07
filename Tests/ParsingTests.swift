@testable import PureXML
import Testing

@Suite("Parsing")
struct ParsingTests {
    @Test("Empty input reports an empty document")
    func test_emptyInputThrows() {
        #expect(throws: PureXML.Parsing.ParseError.emptyDocument) {
            try PureXML.parse("")
        }
    }

    /// The tokenizing parser is not implemented yet. This test pins the current
    /// contract so the gap is explicit rather than a silent partial parse.
    @Test("Non-empty input reports the parser is not implemented yet")
    func test_nonEmptyInputNotImplemented() {
        do {
            _ = try PureXML.parse("<root/>")
            Issue.record("expected parse to throw notImplemented")
        } catch let error as PureXML.Parsing.ParseError {
            guard case .notImplemented = error else {
                Issue.record("expected notImplemented, got \(error)")
                return
            }
        } catch {
            Issue.record("unexpected error: \(error)")
        }
    }
}
