@testable import PureXML
import Testing

@Suite("Schematron abstract rules and extends")
struct SchematronAbstractTests {
    private func validate(_ schema: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml)
    }

    @Test("A concrete rule extends an abstract rule's assertions")
    func test_extends() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule abstract="true" id="hasId">
              <assert test="@id">element needs an id</assert>
            </rule>
            <rule context="item">
              <extends rule="hasId"/>
              <assert test="@name">item needs a name</assert>
            </rule>
          </pattern>
        </schema>
        """
        // Both the inherited and the own assertion hold.
        #expect(try validate(schema, "<item id=\"1\" name=\"x\"/>").isEmpty)
        // The inherited assertion fails (no id).
        #expect(try validate(schema, "<item name=\"x\"/>").count == 1)
        // Both fail.
        #expect(try validate(schema, "<item/>").count == 2)
    }

    @Test("An abstract rule does not fire on its own")
    func test_abstractDoesNotFire() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule abstract="true" id="never" context="thing">
              <assert test="false()">should never run</assert>
            </rule>
          </pattern>
        </schema>
        """
        // No concrete rule extends it, so nothing fires even on a matching element.
        #expect(try validate(schema, "<thing/>").isEmpty)
    }

    @Test("An extends pulls in the abstract rule's let bindings")
    func test_extendsLet() throws {
        let schema = """
        <schema xmlns="http://purl.oclc.org/dsdl/schematron">
          <pattern>
            <rule abstract="true" id="withLimit">
              <let name="limit" value="10"/>
            </rule>
            <rule context="n">
              <extends rule="withLimit"/>
              <assert test="number(.) &lt; $limit">over the limit</assert>
            </rule>
          </pattern>
        </schema>
        """
        #expect(try validate(schema, "<n>5</n>").isEmpty)
        #expect(try !validate(schema, "<n>50</n>").isEmpty)
    }
}
