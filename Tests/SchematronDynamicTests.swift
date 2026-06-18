import Testing
@testable import PureXML

@Suite("Schematron dynamic messages and phases")
struct SchematronDynamicTests {
    private func validate(_ schema: String, _ xml: String, phase: String? = nil) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml, phase: phase)
    }

    @Test("value-of renders the actual value in an assertion message")
    func test_valueOf() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="age">
              <assert test="number(.) &lt; 100">Age <value-of select="."/> must be under 100</assert>
            </rule>
          </pattern>
        </schema>
        """
        let errors = try validate(schema, "<age>120</age>")
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Age 120 must be under 100")
    }

    @Test("name renders the context element's name")
    func test_name() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule context="item">
              <assert test="@id">Element <name/> needs an id</assert>
            </rule>
          </pattern>
        </schema>
        """
        let errors = try validate(schema, "<item/>")
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "Element item needs an id")
    }

    @Test("A phase activates only its listed patterns")
    func test_phase() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <phase id="basic">
            <active pattern="p1"/>
          </phase>
          <pattern id="p1">
            <rule context="a"><assert test="false()">a is bad</assert></rule>
          </pattern>
          <pattern id="p2">
            <rule context="b"><assert test="false()">b is bad</assert></rule>
          </pattern>
        </schema>
        """
        let xml = "<root><a/><b/></root>"
        // The basic phase runs only p1, so only the a-rule fires.
        let basic = try validate(schema, xml, phase: "basic")
        #expect(basic.count == 1)
        #expect(basic.first?.reason == "a is bad")
        // With no phase, every pattern runs.
        #expect(try validate(schema, xml).count == 2)
        // #ALL runs every pattern.
        #expect(try validate(schema, xml, phase: "#ALL").count == 2)
    }

    @Test("defaultPhase scopes patterns when no phase is requested")
    func test_defaultPhase() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron" defaultPhase="only-a">
          <phase id="only-a"><active pattern="p1"/></phase>
          <pattern id="p1"><rule context="a"><assert test="false()">a is bad</assert></rule></pattern>
          <pattern id="p2"><rule context="b"><assert test="false()">b is bad</assert></rule></pattern>
        </schema>
        """
        let errors = try validate(schema, "<root><a/><b/></root>")
        #expect(errors.count == 1)
        #expect(errors.first?.reason == "a is bad")
    }
}
