@testable import PureXML
import Testing

@Suite("Schematron let variables")
struct SchematronLetTests {
    private func validate(_ schema: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    @Test("A let binding is available to the rule's test")
    func test_letInTest() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="order">
              <let name="total" value="sum(item/@price)"/>
              <assert test="$total &lt;= 100">order total exceeds 100</assert>
            </rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<order><item price=\"40\"/><item price=\"50\"/></order>").isEmpty)
        #expect(try !validate(schema, "<order><item price=\"60\"/><item price=\"50\"/></order>").isEmpty)
    }

    @Test("A let binding can be rendered in a message")
    func test_letInMessage() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="age">
              <let name="limit" value="100"/>
              <assert test="number(.) &lt; $limit">Age <value-of select="."/> reaches the limit <value-of select="$limit"/></assert>
            </rule>
          </pattern>
        </schema>
        """
        let errors = try validate(schema, "<age>120</age>")
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Age 120 reaches the limit 100")
    }

    @Test("A later let can reference an earlier one")
    func test_letChaining() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="box">
              <let name="base" value="number(@n)"/>
              <let name="doubled" value="$base * 2"/>
              <assert test="$doubled = 10">doubled is not ten</assert>
            </rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<box n=\"5\"/>").isEmpty)
        #expect(try !validate(schema, "<box n=\"3\"/>").isEmpty)
    }
}
