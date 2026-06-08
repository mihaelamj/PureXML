@testable import PureXML
import Testing

/// The unified lint surface: one source-ranged, severity-tagged list merging
/// parse recovery and schema validation, the way an editor consumes it.
@Suite("Lint")
struct LintTests {
    @Test("A well-formed, valid document lints clean")
    func test_clean() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="n" type="xs:integer"/>
        </xs:schema>
        """
        let schema = try PureXML.Schema.Document(xsd)
        #expect(PureXML.lint("<n>3</n>", validate: schema.validate).isEmpty)
    }

    @Test("Well-formedness alone is linted without a schema")
    func test_parseOnly() {
        let diagnostics = PureXML.lint("<a><b>x")
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].message.contains("unexpected end of input"))
        #expect(diagnostics[0].range != nil)
    }

    @Test("A validation finding is located by source range")
    func test_validationRanged() throws {
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="order">
            <xs:complexType>
              <xs:sequence><xs:element name="qty" type="xs:integer"/></xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let schema = try PureXML.Schema.Document(xsd)
        let diagnostics = PureXML.lint("<order>\n  <qty>lots</qty>\n</order>", validate: schema.validate)
        #expect(diagnostics.count == 1)
        #expect(diagnostics[0].severity == .error)
        #expect(diagnostics[0].range?.start == PureXML.Parsing.Mark(line: 2, column: 3, offset: 10))
    }

    @Test("Validation runs over the recovered tree, so invalid input still lints")
    func test_invalidStillValidates() throws {
        // The document is both not well-formed (truncated) and schema-invalid.
        let xsd = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:element name="order">
            <xs:complexType>
              <xs:sequence><xs:element name="qty" type="xs:integer"/></xs:sequence>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let schema = try PureXML.Schema.Document(xsd)
        let diagnostics = PureXML.lint("<order><qty>lots", validate: schema.validate)
        // One parse diagnostic (truncation) and one validation finding (qty not an integer).
        #expect(diagnostics.contains { $0.message.contains("unexpected end of input") })
        #expect(diagnostics.contains { $0.message.contains("not a valid") })
    }
}
