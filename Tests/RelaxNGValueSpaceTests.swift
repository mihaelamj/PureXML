import Testing
@testable import PureXML

@Suite("RELAX NG typed <value> value-space comparison")
struct RelaxNGValueSpaceTests {
    private let xsd = "http://www.w3.org/2001/XMLSchema-datatypes"

    private func validXML(_ rng: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(rng).validate(xml)
    }

    private func validRNC(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    private func valueElement(_ type: String, _ literal: String) -> String {
        """
        <element name="n" datatypeLibrary="\(xsd)" xmlns="http://relaxng.org/ns/structure/1.0">
          <value type="\(type)">\(literal)</value>
        </element>
        """
    }

    @Test("An integer value matches in value space, not lexically")
    func test_integerValueSpace() throws {
        let rng = valueElement("integer", "1")
        #expect(try validXML(rng, "<n>1</n>"))
        #expect(try validXML(rng, "<n>01</n>"))
        #expect(try validXML(rng, "<n>+1</n>"))
        #expect(try !validXML(rng, "<n>2</n>"))
        #expect(try !validXML(rng, "<n>1x</n>"))
    }

    @Test("A decimal value matches regardless of trailing zeros")
    func test_decimalValueSpace() throws {
        let rng = valueElement("decimal", "1.5")
        #expect(try validXML(rng, "<n>1.5</n>"))
        #expect(try validXML(rng, "<n>1.50</n>"))
        #expect(try validXML(rng, "<n>01.500</n>"))
        #expect(try !validXML(rng, "<n>1.6</n>"))
    }

    @Test("A boolean value treats 1/true and 0/false as equal")
    func test_booleanValueSpace() throws {
        let trueRNG = valueElement("boolean", "true")
        #expect(try validXML(trueRNG, "<n>true</n>"))
        #expect(try validXML(trueRNG, "<n>1</n>"))
        #expect(try !validXML(trueRNG, "<n>false</n>"))
        #expect(try !validXML(trueRNG, "<n>0</n>"))
    }

    @Test("A token value still compares by normalized lexical form")
    func test_tokenLexical() throws {
        // Untyped value defaults to token: whitespace collapses, then compares.
        let rng = """
        <element name="flag" xmlns="http://relaxng.org/ns/structure/1.0">
          <value>yes please</value>
        </element>
        """
        #expect(try validXML(rng, "<flag>yes please</flag>"))
        #expect(try validXML(rng, "<flag>   yes    please   </flag>"))
        #expect(try !validXML(rng, "<flag>no</flag>"))
    }

    @Test("A string value preserves and compares exactly after the type's whitespace rule")
    func test_stringPreserve() throws {
        let rng = valueElement("string", "abc")
        #expect(try validXML(rng, "<n>abc</n>"))
        #expect(try !validXML(rng, "<n>abcd</n>"))
    }

    @Test("Compact syntax typed value compares in value space")
    func test_compactIntegerValue() throws {
        let rnc = """
        namespace x = "urn:x"
        element n { xsd:integer "10" }
        """
        #expect(try validRNC(rnc, "<n>10</n>"))
        #expect(try validRNC(rnc, "<n>010</n>"))
        #expect(try !validRNC(rnc, "<n>11</n>"))
    }

    @Test("Compact bare string literal is a token value")
    func test_compactBareLiteral() throws {
        let rnc = "element flag { \"on\" }"
        #expect(try validRNC(rnc, "<flag>on</flag>"))
        #expect(try validRNC(rnc, "<flag>  on  </flag>"))
        #expect(try !validRNC(rnc, "<flag>off</flag>"))
    }

    @Test("SimpleType.valueMatches compares numeric value space directly")
    func test_valueMatchesUnit() {
        let integer = PureXML.Schema.SimpleType(base: .integer)
        #expect(integer.valueMatches("007", literal: "7"))
        #expect(!integer.valueMatches("7", literal: "8"))
        let token = PureXML.Schema.SimpleType(base: .token)
        #expect(token.valueMatches("  a  b ", literal: "a b"))
        #expect(!token.valueMatches("a b", literal: "ab"))
    }
}
