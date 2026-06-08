@testable import PureXML
import Testing

@Suite("RELAX NG")
struct RelaxNGTests {
    private func valid(_ rng: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(rng).validate(xml)
    }

    private let rngNamespace = "xmlns=\"http://relaxng.org/ns/structure/1.0\""

    @Test("An element with text content")
    func test_elementText() throws {
        let rng = "<element name=\"greeting\" \(rngNamespace)><text/></element>"
        #expect(try valid(rng, "<greeting>hello</greeting>"))
        #expect(try !valid(rng, "<other>hello</other>"))
        #expect(try !valid(rng, "<greeting><child/></greeting>"))
    }

    @Test("A sequence of child elements in order")
    func test_sequence() throws {
        let rng = """
        <element name="book" \(rngNamespace)>
          <element name="title"><text/></element>
          <element name="author"><text/></element>
        </element>
        """
        #expect(try valid(rng, "<book><title>T</title><author>A</author></book>"))
        #expect(try !valid(rng, "<book><author>A</author><title>T</title></book>"))
        #expect(try !valid(rng, "<book><title>T</title></book>"))
    }

    @Test("choice, optional, and zeroOrMore")
    func test_combinators() throws {
        let rng = """
        <element name="r" \(rngNamespace)>
          <optional><element name="a"><text/></element></optional>
          <zeroOrMore><element name="b"><empty/></element></zeroOrMore>
          <choice><element name="x"><empty/></element><element name="y"><empty/></element></choice>
        </element>
        """
        #expect(try valid(rng, "<r><a>1</a><b/><b/><x/></r>"))
        #expect(try valid(rng, "<r><y/></r>"))
        #expect(try !valid(rng, "<r><x/><y/></r>"))
    }

    @Test("oneOrMore requires at least one")
    func test_oneOrMore() throws {
        let rng = """
        <element name="list" \(rngNamespace)>
          <oneOrMore><element name="item"><text/></element></oneOrMore>
        </element>
        """
        #expect(try valid(rng, "<list><item>a</item><item>b</item></list>"))
        #expect(try !valid(rng, "<list></list>"))
    }

    @Test("Attributes are validated and required")
    func test_attributes() throws {
        let rng = """
        <element name="e" \(rngNamespace)>
          <attribute name="id"><text/></attribute>
          <empty/>
        </element>
        """
        #expect(try valid(rng, "<e id=\"1\"/>"))
        #expect(try !valid(rng, "<e/>"))
    }

    @Test("interleave allows children in any order")
    func test_interleave() throws {
        let rng = """
        <element name="r" \(rngNamespace)>
          <interleave>
            <element name="a"><empty/></element>
            <element name="b"><empty/></element>
          </interleave>
        </element>
        """
        #expect(try valid(rng, "<r><a/><b/></r>"))
        #expect(try valid(rng, "<r><b/><a/></r>"))
        #expect(try !valid(rng, "<r><a/></r>"))
    }

    @Test("data types validate text content")
    func test_data() throws {
        let rng = "<element name=\"age\" \(rngNamespace)><data type=\"int\"/></element>"
        #expect(try valid(rng, "<age>42</age>"))
        #expect(try !valid(rng, "<age>x</age>"))
    }

    @Test("value matches a literal")
    func test_value() throws {
        let rng = "<element name=\"flag\" \(rngNamespace)><value>yes</value></element>"
        #expect(try valid(rng, "<flag>yes</flag>"))
        #expect(try !valid(rng, "<flag>no</flag>"))
    }

    @Test("A grammar with define and ref validates recursive structures")
    func test_recursiveGrammar() throws {
        let rng = """
        <grammar \(rngNamespace)>
          <start><ref name="node"/></start>
          <define name="node">
            <element name="node">
              <optional><ref name="node"/></optional>
            </element>
          </define>
        </grammar>
        """
        #expect(try valid(rng, "<node/>"))
        #expect(try valid(rng, "<node><node><node/></node></node>"))
        #expect(try !valid(rng, "<node><other/></node>"))
    }
}
