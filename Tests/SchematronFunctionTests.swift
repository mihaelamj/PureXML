import Testing
@testable import PureXML

@Suite("Schematron key()/document()/current() in tests")
struct SchematronFunctionTests {
    private func validate(_ schema: String, _ xml: String, loader: @escaping (String) -> String? = { _ in nil }) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Validation.Schematron(schema: schema).validate(xml, documentLoader: loader)
    }

    private let sch = "http://purl.oclc.org/dsdl/schematron"
    private let xsl = "http://www.w3.org/1999/XSL/Transform"

    @Test("key() resolves a node by an xsl:key index")
    func test_key() throws {
        let schema = """
        <schema xmlns="\(sch)" xmlns:xsl="\(xsl)">
          <xsl:key name="byId" match="item" use="@id"/>
          <pattern>
            <rule context="ref">
              <assert test="key('byId', @to)">no item with that id</assert>
            </rule>
          </pattern>
        </schema>
        """
        // ref/@to=a resolves to item id=a; ref/@to=z resolves to nothing -> one failure.
        let xml = "<root><item id='a'/><item id='b'/><ref to='a'/><ref to='z'/></root>"
        let errors = try validate(schema, xml)
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("no item") == true)
    }

    @Test("document() loads an external file for cross-document checks")
    func test_document() throws {
        let schema = """
        <schema xmlns="\(sch)">
          <pattern>
            <rule context="ref">
              <assert test="@to = document('allowed.xml')/allowed/id">id is not in the allowed list</assert>
            </rule>
          </pattern>
        </schema>
        """
        let allowed = "<allowed><id>a</id><id>b</id></allowed>"
        let xml = "<root><ref to='a'/><ref to='x'/></root>"
        let errors = try validate(schema, xml) { $0 == "allowed.xml" ? allowed : nil }
        #expect(errors.count == 1)
        #expect(errors.first?.reason.contains("not in the allowed") == true)
    }

    @Test("current() refers to the rule's context node inside a predicate")
    func test_current() throws {
        let schema = """
        <schema xmlns="\(sch)">
          <pattern>
            <rule context="item">
              <assert test="//item[@id = current()/@ref]">the referenced item must exist</assert>
            </rule>
          </pattern>
        </schema>
        """
        // item ref=b resolves (item id=b exists); item ref=z does not -> one failure.
        let xml = "<root><item id='a' ref='b'/><item id='b' ref='z'/></root>"
        let errors = try validate(schema, xml)
        #expect(errors.count == 1)
    }

    @Test("A schema without these functions still validates")
    func test_plain() throws {
        let schema = """
        <schema xmlns="\(sch)">
          <pattern><rule context="n"><assert test="number(.) &lt; 10">too big</assert></rule></pattern>
        </schema>
        """
        #expect(try validate(schema, "<n>5</n>").isEmpty)
        #expect(try !validate(schema, "<n>50</n>").isEmpty)
    }
}
