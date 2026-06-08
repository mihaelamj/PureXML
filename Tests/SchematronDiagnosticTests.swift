@testable import PureXML
import Testing

@Suite("Schematron diagnostics")
struct SchematronDiagnosticTests {
    private func validate(_ schema: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    @Test("A referenced diagnostic is appended to the failure message")
    func test_diagnostic() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="age">
              <assert test="number(.) &lt; 100" diagnostics="d1">age too high</assert>
            </rule>
          </pattern>
          <diagnostics>
            <diagnostic id="d1">got <value-of select="."/></diagnostic>
          </diagnostics>
        </schema>
        """
        let errors = try validate(schema, "<age>120</age>")
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "age too high got 120")
    }

    @Test("Multiple diagnostics are appended in order")
    func test_multipleDiagnostics() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="x">
              <assert test="false()" diagnostics="a b">bad</assert>
            </rule>
          </pattern>
          <diagnostics>
            <diagnostic id="a">first</diagnostic>
            <diagnostic id="b">second</diagnostic>
          </diagnostics>
        </schema>
        """
        #expect(try validate(schema, "<x/>").first?.reason == "bad first second")
    }

    @Test("An assertion with no diagnostics renders only its message")
    func test_noDiagnostics() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="x"><assert test="false()">plain</assert></rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<x/>").first?.reason == "plain")
    }
}
