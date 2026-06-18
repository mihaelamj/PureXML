import Testing
@testable import PureXML

/// Schema-correctness validation (#131): a RELAX NG schema document must
/// itself match the RELAX NG grammar (section 3) and the restrictions of
/// 4.16-4.19 and 7.1-7.4 before any pattern interpretation.
@Suite("RELAX NG schema correctness")
struct RelaxNGSchemaCorrectnessTests {
    private func rejects(_ rng: String) -> Bool {
        (try? PureXML.Schema.RelaxNG(rng)) == nil
    }

    private let rngNS = "xmlns=\"http://relaxng.org/ns/structure/1.0\""

    @Test("Junk, misplaced elements, and illegal attributes are schema errors")
    func test_grammarLevel() {
        #expect(rejects("<thisIsJunk/>"))
        #expect(rejects("<grammar \(rngNS)><element name=\"foo\"><empty/></element></grammar>"))
        #expect(rejects("<element \(rngNS) name=\"foo\" bogus=\"x\"><empty/></element>"))
        #expect(rejects("<element \(rngNS) name=\"foo\"/>"))
        #expect(rejects("<ref \(rngNS)/>"))
        #expect(!rejects("<element \(rngNS) name=\"foo\"><empty/></element>"))
    }

    @Test("4.16: except restrictions and the xmlns prohibition")
    func test_section416() {
        #expect(rejects("<element \(rngNS) name=\"f\"><anyName><except><anyName/></except></anyName><empty/></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><attribute name=\"xmlns\"><text/></attribute></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><attribute ns=\"http://www.w3.org/2000/xmlns\" name=\"b\"><text/></attribute></element>"))
    }

    @Test("4.17/4.19: combine conflicts and unguarded recursion")
    func test_grammarSemantics() {
        let conflict = """
        <grammar \(rngNS)><start><ref name="x"/></start>
        <define name="x" combine="choice"><empty/></define>
        <define name="x" combine="interleave"><empty/></define></grammar>
        """
        #expect(rejects(conflict))
        let recursion = """
        <grammar \(rngNS)><start><ref name="x"/></start>
        <define name="x"><optional><ref name="x"/></optional></define></grammar>
        """
        #expect(rejects(recursion))
        #expect(rejects("<grammar \(rngNS)><start><ref name=\"missing\"/></start></grammar>"))
    }

    @Test("7.1-7.4: prohibited paths, content types, attributes, interleave")
    func test_section7() {
        #expect(rejects("<element \(rngNS) name=\"f\"><attribute name=\"a\"><attribute name=\"b\"/></attribute></element>"))
        #expect(rejects("<grammar \(rngNS)><start><attribute name=\"a\"/></start></grammar>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><group><data type=\"token\"/><data type=\"token\"/></group></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><attribute name=\"b\"/><attribute name=\"b\"/></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><interleave><text/><text/></interleave></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\"><attribute><anyName/><text/></attribute></element>"))
        // The same shapes inside a notAllowed branch are normalized away (4.20).
        let normalized = """
        <element \(rngNS) name="f"><choice><empty/><group><notAllowed/>
        <attribute name="a"><attribute name="b"/></attribute></group></choice></element>
        """
        #expect(!rejects(normalized))
    }

    @Test("Datatype and URI checks")
    func test_datatypes() {
        #expect(rejects("<element \(rngNS) name=\"f\"><data type=\"decimal\"/></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\" datatypeLibrary=\"foo_bar:x\"><empty/></element>"))
        #expect(rejects("<element \(rngNS) name=\"f\" datatypeLibrary=\"http://e.com#frag\"><empty/></element>"))
    }
}
