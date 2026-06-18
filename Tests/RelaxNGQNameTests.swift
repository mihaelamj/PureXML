import Testing
@testable import PureXML

/// The QName datatype's dual-context value space (#131): the schema side
/// resolves the literal against the schema's xmlns/ns scope at compile, and
/// the instance side resolves the text against the instance element's
/// in-scope namespaces at validation, in both tree and streaming modes.
@Suite("RELAX NG QName values")
struct RelaxNGQNameTests {
    private let schema = """
    <element name="e:foo" xmlns:e="http://www.example.com/1" xmlns="http://relaxng.org/ns/structure/1.0">
      <value type="QName" ns="http://www.example.com/2" datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes">xyzzy</value>
    </element>
    """

    @Test("Prefixed and default-namespace instance QNames resolve; unbound ones fail")
    func test_dualContextResolution() throws {
        let compiled = try PureXML.Schema.RelaxNG(schema)
        let prefixed = "<e1:foo xmlns:e1=\"http://www.example.com/1\" xmlns:e2=\"http://www.example.com/2\">e2:xyzzy</e1:foo>"
        #expect(try compiled.validate(prefixed))
        let viaDefault = "<e1:foo xmlns:e1=\"http://www.example.com/1\" xmlns=\"http://www.example.com/2\">xyzzy</e1:foo>"
        #expect(try compiled.validate(viaDefault))
        let unbound = "<e1:foo xmlns:e1=\"http://www.example.com/1\">xyzzy</e1:foo>"
        #expect(try !compiled.validate(unbound))
        let wrongNamespace = "<e1:foo xmlns:e1=\"http://www.example.com/1\" xmlns=\"http://www.example.com/other\">xyzzy</e1:foo>"
        #expect(try !compiled.validate(wrongNamespace))
        // Streaming agrees with the tree walk.
        #expect(try compiled.validate(streaming: prefixed))
        #expect(try !compiled.validate(streaming: unbound))
    }

    @Test("A schema-side prefixed literal resolves against schema declarations")
    func test_schemaSidePrefix() throws {
        let prefixedLiteral = """
        <element name="foo" xmlns:e3="http://www.example.com/2" xmlns="http://relaxng.org/ns/structure/1.0">
          <value type="QName" datatypeLibrary="http://www.w3.org/2001/XMLSchema-datatypes">e3:xyzzy</value>
        </element>
        """
        let compiled = try PureXML.Schema.RelaxNG(prefixedLiteral)
        #expect(try compiled.validate("<foo xmlns:q=\"http://www.example.com/2\">q:xyzzy</foo>"))
        #expect(try !compiled.validate("<foo>xyzzy</foo>"))
    }
}
