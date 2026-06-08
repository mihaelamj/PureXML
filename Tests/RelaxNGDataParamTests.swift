@testable import PureXML
import Testing

@Suite("RELAX NG data param facets")
struct RelaxNGDataParamTests {
    private let rngNamespace = "xmlns=\"http://relaxng.org/ns/structure/1.0\" datatypeLibrary=\"http://www.w3.org/2001/XMLSchema-datatypes\""

    private func valid(_ rng: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(rng).validate(xml)
    }

    @Test("A minLength param constrains a data value")
    func test_minLength() throws {
        let rng = """
        <element name="code" \(rngNamespace)>
          <data type="string"><param name="minLength">3</param></data>
        </element>
        """
        #expect(try valid(rng, "<code>abc</code>"))
        #expect(try !valid(rng, "<code>ab</code>"))
    }

    @Test("A maxInclusive param constrains a numeric data value")
    func test_maxInclusive() throws {
        let rng = """
        <element name="n" \(rngNamespace)>
          <data type="integer"><param name="maxInclusive">10</param></data>
        </element>
        """
        #expect(try valid(rng, "<n>5</n>"))
        #expect(try !valid(rng, "<n>20</n>"))
    }

    @Test("A pattern param constrains a data value")
    func test_pattern() throws {
        let rng = """
        <element name="sku" \(rngNamespace)>
          <data type="string"><param name="pattern">[A-Z]{3}</param></data>
        </element>
        """
        #expect(try valid(rng, "<sku>ABC</sku>"))
        #expect(try !valid(rng, "<sku>abc</sku>"))
    }

    @Test("Data with no params still validates against its base type")
    func test_noParams() throws {
        let rng = "<element name=\"n\" \(rngNamespace)><data type=\"integer\"/></element>"
        #expect(try valid(rng, "<n>42</n>"))
        #expect(try !valid(rng, "<n>x</n>"))
    }
}
