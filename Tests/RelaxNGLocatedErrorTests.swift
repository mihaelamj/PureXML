import Testing
@testable import PureXML

@Suite("RELAX NG located, recovering validation errors")
struct RelaxNGLocatedErrorTests {
    private func errors(_ rng: String, _ xml: String) throws -> [PureXML.Validation.ValidationError] {
        try PureXML.Schema.RelaxNG(rng).errors(in: xml)
    }

    private func reasons(_ rng: String, _ xml: String) throws -> [String] {
        try errors(rng, xml).map(\.reason)
    }

    private func paths(_ rng: String, _ xml: String) throws -> [[String]] {
        try errors(rng, xml).map { $0.codingPath.map(\.stringValue) }
    }

    private let twoChildren = """
    <element name="root" xmlns="http://relaxng.org/ns/structure/1.0">
      <element name="a"><element name="x"><empty/></element></element>
      <element name="b"><element name="y"><empty/></element></element>
    </element>
    """

    @Test("A valid document yields no errors")
    func test_valid() throws {
        #expect(try errors(twoChildren, "<root><a><x/></a><b><y/></b></root>").isEmpty)
    }

    @Test("Two independent subtree errors are both reported (recovery, not one error)")
    func test_multipleErrorsWithRecovery() throws {
        let xml = "<root><a><wrong/></a><b><alsowrong/></b></root>"
        let found = try errors(twoChildren, xml)
        #expect(found.count == 2)
        let reasons = found.map(\.reason)
        #expect(reasons.contains { $0.contains("<wrong>") && $0.contains("<a>") })
        #expect(reasons.contains { $0.contains("<alsowrong>") && $0.contains("<b>") })
    }

    @Test("Each error is located at the offending nested element")
    func test_locatedPaths() throws {
        let xml = "<root><a><wrong/></a><b><alsowrong/></b></root>"
        let located = try paths(twoChildren, xml)
        #expect(located.contains(["root", "a", "wrong"]))
        #expect(located.contains(["root", "b", "alsowrong"]))
    }

    @Test("An unexpected element carries an expected-content recovery hint")
    func test_expectedHint() throws {
        let xml = "<root><a><wrong/></a><b><y/></b></root>"
        let found = try reasons(twoChildren, xml)
        #expect(found.count == 1)
        #expect(found.first?.contains("expected <x>") == true)
    }

    @Test("Missing required content is reported with what was expected")
    func test_missingContent() throws {
        let xml = "<root><a><x/></a></root>"
        let found = try reasons(twoChildren, xml)
        #expect(found.contains { $0.contains("missing required content") && $0.contains("<b>") })
    }

    @Test("An extra trailing element is reported as unexpected")
    func test_extraElement() throws {
        let xml = "<root><a><x/></a><b><y/></b><c/></root>"
        let found = try errors(twoChildren, xml)
        #expect(found.count == 1)
        #expect(found.first?.reason.contains("<c>") == true)
    }

    @Test("An invalid attribute value is located on its element")
    func test_attribute() throws {
        let rng = """
        <element name="n" datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes" xmlns="http://relaxng.org/ns/structure/1.0">
          <attribute name="count"><data type="integer"/></attribute>
        </element>
        """
        let found = try errors(rng, "<n count='abc'/>")
        #expect(found.count == 1)
        #expect(found.first?.reason.contains("@count") == true)
        // The declared attribute's bad value is quoted and the type named.
        #expect(found.first?.reason.contains("'abc'") == true)
        #expect(found.first?.reason.contains("integer") == true)
        #expect(found.first?.codingPath.map(\.stringValue) == ["n", "@count"])
    }

    @Test("An undeclared attribute is distinguished from a bad value")
    func test_undeclaredAttribute() throws {
        let rng = """
        <element name="n" xmlns="http://relaxng.org/ns/structure/1.0">
          <attribute name="a"><text/></attribute>
        </element>
        """
        let found = try errors(rng, "<n a='x' b='y'/>")
        #expect(found.count == 1)
        #expect(found.first?.reason.contains("@b") == true)
        #expect(found.first?.reason.contains("is not allowed") == true)
    }

    @Test("Invalid datatype content is located on the element")
    func test_dataValue() throws {
        let rng = """
        <element name="n" datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes" xmlns="http://relaxng.org/ns/structure/1.0">
          <data type="integer"/>
        </element>
        """
        let found = try reasons(rng, "<n>abc</n>")
        #expect(found.contains { $0.contains("<n>") })
        // The message quotes the offending value and names the expected datatype.
        #expect(found.contains { $0.contains("'abc'") && $0.contains("integer") })
    }

    @Test("A value mismatch quotes both the actual text and the required literal")
    func test_valueMismatchDetail() throws {
        let rng = """
        <element name="flag" xmlns="http://relaxng.org/ns/structure/1.0">
          <value>on</value>
        </element>
        """
        let found = try reasons(rng, "<flag>off</flag>")
        #expect(found.contains { $0.contains("'off'") && $0.contains("'on'") })
    }

    @Test("The validation() value composes with the framework like the other validators")
    func test_validationValueForm() throws {
        let schema = try PureXML.Schema.RelaxNG(twoChildren)
        let node = try PureXML.parse("<root><a><wrong/></a><b><alsowrong/></b></root>")
        let collected = PureXML.Validation.Validator<Void>.blank
            .validating(schema.validation())
            .errors(for: node, in: ())
        #expect(collected.count == 2)
    }

    @Test("The same value-space datatypes still validate through located errors")
    func test_compactSchema() throws {
        let schema = try PureXML.Schema.RelaxNG(compact: "element greeting { \"hi\" }")
        #expect(try schema.errors(in: "<greeting>hi</greeting>").isEmpty)
        #expect(try !schema.errors(in: "<greeting>bye</greeting>").isEmpty)
    }
}
