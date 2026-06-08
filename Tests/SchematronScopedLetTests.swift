@testable import PureXML
import Testing

@Suite("Schematron schema- and pattern-level let")
struct SchematronScopedLetTests {
    private func validate(_ schema: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    @Test("A schema-level let is available to every rule")
    func test_schemaLet() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <let name="limit" value="10"/>
          <pattern>
            <rule context="n">
              <assert test="number(.) &lt; $limit">over the schema limit</assert>
            </rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<n>5</n>").isEmpty)
        #expect(try !validate(schema, "<n>50</n>").isEmpty)
    }

    @Test("A pattern-level let is available to the pattern's rules")
    func test_patternLet() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <let name="want" value="'yes'"/>
            <rule context="flag">
              <assert test=". = $want">flag must be yes</assert>
            </rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<flag>yes</flag>").isEmpty)
        #expect(try !validate(schema, "<flag>no</flag>").isEmpty)
    }

    @Test("A rule-level let overrides a wider-scope let of the same name")
    func test_ruleOverridesSchema() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <let name="limit" value="100"/>
          <pattern>
            <rule context="n">
              <let name="limit" value="10"/>
              <assert test="number(.) &lt; $limit">over the rule limit</assert>
            </rule>
          </pattern>
        </schema>
        """
        // The rule's limit (10) wins over the schema's (100).
        #expect(try !validate(schema, "<n>50</n>").isEmpty)
    }
}
