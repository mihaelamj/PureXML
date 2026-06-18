import Testing
@testable import PureXML

@Suite("Schematron abstract patterns (is-a / param)")
struct SchematronAbstractPatternTests {
    private func validate(_ schema: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    private func reasons(_ schema: String, _ xml: String) throws -> [String] {
        try validate(schema, xml).map(\.reason)
    }

    @Test("An is-a pattern substitutes $params into context and test")
    func test_paramSubstitution() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern abstract="true" id="required">
            <rule context="$element">
              <assert test="$attribute">missing</assert>
            </rule>
          </pattern>
          <pattern is-a="required" id="car-needs-wheels">
            <param name="element" value="car"/>
            <param name="attribute" value="@wheels"/>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<car wheels='4'/>").isEmpty)
        let failed = try reasons(schema, "<car/>")
        #expect(failed.count == 1)
        #expect(failed.first?.contains("missing") == true)
    }

    @Test("The abstract template itself is not evaluated")
    func test_abstractTemplateInert() throws {
        // $ctx as a raw context would select nothing useful if evaluated; the
        // template must contribute no rules of its own.
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern abstract="true" id="t">
            <rule context="$ctx"><assert test="$cond">x</assert></rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<doc/>").isEmpty)
    }

    @Test("One template instantiates for two different concrete patterns")
    func test_reuseTemplate() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern abstract="true" id="present">
            <rule context="$el"><assert test="count(.) = 1">absent</assert></rule>
          </pattern>
          <pattern is-a="present" id="a"><param name="el" value="alpha"/></pattern>
          <pattern is-a="present" id="b"><param name="el" value="beta"/></pattern>
        </schema>
        """
        #expect(try validate(schema, "<root><alpha/><beta/></root>").isEmpty)
    }

    @Test("A longer param name is not captured by a shorter one")
    func test_noPrefixCapture() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern abstract="true" id="t">
            <rule context="$n"><assert test="@$nm = 'ok'">bad</assert></rule>
          </pattern>
          <pattern is-a="t" id="c">
            <param name="n" value="item"/>
            <param name="nm" value="status"/>
          </pattern>
        </schema>
        """
        // $nm must map to "status", not be eaten by $n -> "item" + "m".
        #expect(try validate(schema, "<item status='ok'/>").isEmpty)
        #expect(try !validate(schema, "<item status='no'/>").isEmpty)
    }

    @Test("A $name that is not a param (an ordinary let variable) is preserved")
    func test_letVariablePreserved() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern abstract="true" id="t">
            <rule context="$el">
              <let name="actual" value="@count"/>
              <assert test="$actual = $expected">wrong count</assert>
            </rule>
          </pattern>
          <pattern is-a="t" id="c">
            <param name="el" value="bag"/>
            <param name="expected" value="3"/>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<bag count='3'/>").isEmpty)
        #expect(try !validate(schema, "<bag count='2'/>").isEmpty)
    }
}
