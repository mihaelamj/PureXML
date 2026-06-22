import Testing
@testable import PureXML

/// RELAX NG `include` and `externalRef` resolution (Sources/Schema/RelaxNGParserIncludes.swift),
/// which a loader supplies. This path was under-covered; these exercise a plain
/// include, an include with a `define` override, and an externalRef.
@Suite("RELAX NG include / externalRef")
struct RelaxNGIncludeTests {
    private let namespace = "xmlns='http://relaxng.org/ns/structure/1.0'"

    @Test("a plain include merges the loaded grammar's defines")
    func test_plainInclude() throws {
        let main = """
        <grammar \(namespace)>
          <include href='lib.rng'/>
          <start><ref name='root'/></start>
        </grammar>
        """
        let lib = """
        <grammar \(namespace)>
          <define name='root'><element name='root'><text/></element></define>
        </grammar>
        """
        let schema = try PureXML.Schema.RelaxNG(main, schemaLoader: { $0 == "lib.rng" ? lib : nil })
        #expect(try schema.validate("<root>hi</root>"))
        #expect(try !schema.validate("<other/>"))
    }

    @Test("an include override replaces the included define")
    func test_includeOverride() throws {
        // The includer redefines `body`; the loaded grammar's `body` (which allows
        // text) is dropped in favor of the override (which allows only empty content).
        let main = """
        <grammar \(namespace)>
          <include href='lib.rng'>
            <define name='body'><element name='root'><empty/></element></define>
          </include>
          <start><ref name='body'/></start>
        </grammar>
        """
        let lib = """
        <grammar \(namespace)>
          <define name='body'><element name='root'><text/></element></define>
        </grammar>
        """
        let schema = try PureXML.Schema.RelaxNG(main, schemaLoader: { $0 == "lib.rng" ? lib : nil })
        #expect(try schema.validate("<root/>")) // override: empty content allowed
        #expect(try !schema.validate("<root>text</root>")) // override removed the text pattern
    }

    @Test("an externalRef pulls a pattern from another document")
    func test_externalRef() throws {
        let main = """
        <grammar \(namespace)>
          <start><externalRef href='frag.rng'/></start>
        </grammar>
        """
        let frag = "<element name='root' \(namespace)><text/></element>"
        let schema = try PureXML.Schema.RelaxNG(main, schemaLoader: { $0 == "frag.rng" ? frag : nil })
        #expect(try schema.validate("<root>x</root>"))
        #expect(try !schema.validate("<nope/>"))
    }
}
