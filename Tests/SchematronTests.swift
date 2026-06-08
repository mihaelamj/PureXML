@testable import PureXML
import Testing

@Suite("Schematron")
struct SchematronTests {
    private let schema = """
    <schema xmlns="http://purl.oclc.org/dsdl/schematron">
      <pattern>
        <rule context="book">
          <assert test="title">a book must have a title</assert>
          <assert test="@isbn">a book must have an isbn</assert>
          <report test="count(author) &gt; 2">more than two authors</report>
        </rule>
      </pattern>
    </schema>
    """

    private func validate(_ xml: String) throws -> [PureXML.Validation.Issue] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    @Test("A conforming document produces no issues")
    func test_valid() throws {
        let xml = "<library><book isbn=\"1\"><title>T</title><author>A</author></book></library>"
        #expect(try validate(xml).isEmpty)
    }

    @Test("A failed assert is reported as an error")
    func test_failedAssert() throws {
        let xml = "<library><book isbn=\"1\"><author>A</author></book></library>"
        let issues = try validate(xml)
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .error)
        #expect(issues.first?.message == "a book must have a title")
    }

    @Test("Multiple failed asserts each report")
    func test_multipleAsserts() throws {
        let xml = "<library><book><author>A</author></book></library>"
        let messages = try validate(xml).map(\.message)
        #expect(messages.contains("a book must have a title"))
        #expect(messages.contains("a book must have an isbn"))
    }

    @Test("A matched report is a warning")
    func test_report() throws {
        let xml = "<library><book isbn=\"1\"><title>T</title>"
            + "<author>A</author><author>B</author><author>C</author></book></library>"
        let issues = try validate(xml)
        #expect(issues.count == 1)
        #expect(issues.first?.severity == .warning)
        #expect(issues.first?.message == "more than two authors")
    }

    @Test("Rules fire once per matching node across the document")
    func test_perNode() throws {
        let xml = "<library>"
            + "<book isbn=\"1\"><title>T</title></book>"
            + "<book><author>A</author></book>"
            + "</library>"
        // The second book is missing both title and isbn.
        let issues = try validate(xml)
        #expect(issues.count == 2)
        #expect(issues.allSatisfy { $0.severity == .error })
    }

    @Test("An invalid test expression is rejected at compile time")
    func test_invalidSchema() {
        let bad = """
        <schema><pattern><rule context="book"><assert test="(">x</assert></rule></pattern></schema>
        """
        #expect(throws: Error.self) {
            _ = try PureXML.Validation.Schematron(schema: bad)
        }
    }
}
