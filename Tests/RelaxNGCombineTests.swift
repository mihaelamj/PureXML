@testable import PureXML
import Testing

@Suite("RELAX NG combine on define")
struct RelaxNGCombineTests {
    private let rngNamespace = "xmlns=\"http://relaxng.org/ns/structure/1.0\""

    private func valid(_ rng: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(rng).validate(xml)
    }

    @Test("combine=choice merges two definitions of the same name as a choice")
    func test_combineChoice() throws {
        let rng = """
        <grammar \(rngNamespace)>
          <start><ref name="content"/></start>
          <define name="content"><element name="a"><empty/></element></define>
          <define name="content" combine="choice"><element name="b"><empty/></element></define>
        </grammar>
        """
        // Both alternatives validate against the merged choice.
        #expect(try valid(rng, "<a/>"))
        #expect(try valid(rng, "<b/>"))
        #expect(try !valid(rng, "<c/>"))
    }

    @Test("combine=interleave merges two definitions as an interleave")
    func test_combineInterleave() throws {
        let rng = """
        <grammar \(rngNamespace)>
          <start><element name="root"><ref name="content"/></element></start>
          <define name="content"><element name="a"><empty/></element></define>
          <define name="content" combine="interleave"><element name="b"><empty/></element></define>
        </grammar>
        """
        // Interleave admits the two children in either order.
        #expect(try valid(rng, "<root><a/><b/></root>"))
        #expect(try valid(rng, "<root><b/><a/></root>"))
        // Both are required by the interleave, so one alone fails.
        #expect(try !valid(rng, "<root><a/></root>"))
    }

    @Test("A plain redefinition without combine still replaces")
    func test_plainRedefinitionReplaces() throws {
        let rng = """
        <grammar \(rngNamespace)>
          <start><ref name="content"/></start>
          <define name="content"><element name="a"><empty/></element></define>
          <define name="content"><element name="b"><empty/></element></define>
        </grammar>
        """
        #expect(try !valid(rng, "<a/>"))
        #expect(try valid(rng, "<b/>"))
    }
}
