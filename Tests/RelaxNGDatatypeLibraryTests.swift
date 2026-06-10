@testable import PureXML
import Testing

@Suite("RELAX NG datatypeLibrary resolution and nsName subtraction")
struct RelaxNGDatatypeLibraryTests {
    private let xsd = "http://www.w3.org/2001/XMLSchema-datatypes"

    private func validXML(_ rng: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(rng).validate(xml)
    }

    private func validRNC(_ rnc: String, _ xml: String) throws -> Bool {
        try PureXML.Schema.RelaxNG(compact: rnc).validate(xml)
    }

    @Test("The default library defines only string and token")
    func test_defaultLibraryStringToken() throws {
        let rng = """
        <element name="v" xmlns="http://relaxng.org/ns/structure/1.0">
          <data type="token"/>
        </element>
        """
        #expect(try validXML(rng, "<v>anything here</v>"))
    }

    @Test("An XSD type without the XSD library is a schema error")
    func test_unknownTypeInDefaultLibrary() throws {
        let rng = """
        <element name="n" xmlns="http://relaxng.org/ns/structure/1.0">
          <data type="integer"/>
        </element>
        """
        // The default library defines only string and token; an unknown
        // datatype is a schema error (the spec suite's incorrect class), not
        // a match-nothing pattern.
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.RelaxNG(rng)
        }
    }

    @Test("Declaring the XSD datatypeLibrary makes xsd types resolve")
    func test_xsdLibraryResolves() throws {
        let rng = """
        <element name="n" datatypeLibrary="\(xsd)" xmlns="http://relaxng.org/ns/structure/1.0">
          <data type="integer"/>
        </element>
        """
        #expect(try validXML(rng, "<n>5</n>"))
        #expect(try !validXML(rng, "<n>x</n>"))
    }

    @Test("datatypeLibrary is inherited from an ancestor element")
    func test_libraryInheritedFromAncestor() throws {
        let rng = """
        <grammar datatypeLibrary="\(xsd)" xmlns="http://relaxng.org/ns/structure/1.0">
          <start>
            <element name="n"><data type="integer"/></element>
          </start>
        </grammar>
        """
        #expect(try validXML(rng, "<n>42</n>"))
        #expect(try !validXML(rng, "<n>4.2</n>"))
    }

    @Test("A value with an unknown explicit type is a schema error")
    func test_unknownValueType() throws {
        let rng = """
        <element name="n" xmlns="http://relaxng.org/ns/structure/1.0">
          <value type="integer">5</value>
        </element>
        """
        #expect(throws: PureXML.Schema.SchemaError.self) {
            _ = try PureXML.Schema.RelaxNG(rng)
        }
    }

    @Test("nsName with except excludes a name in the namespace")
    func test_nsNameExceptXML() throws {
        let rng = """
        <element name="root" xmlns="http://relaxng.org/ns/structure/1.0">
          <element>
            <nsName ns="urn:x"><except><name ns="urn:x">skip</name></except></nsName>
            <empty/>
          </element>
        </element>
        """
        // Any element in urn:x except local name "skip" is allowed.
        let allowed = "<root xmlns:p=\"urn:x\"><p:keep/></root>"
        let excluded = "<root xmlns:p=\"urn:x\"><p:skip/></root>"
        let wrongNS = "<root xmlns:p=\"urn:y\"><p:keep/></root>"
        #expect(try validXML(rng, allowed))
        #expect(try !validXML(rng, excluded))
        #expect(try !validXML(rng, wrongNS))
    }

    @Test("RNC ns:* wildcard matches any name in the namespace")
    func test_rncNsWildcard() throws {
        let rnc = """
        namespace p = "urn:x"
        element root { element p:* { empty } }
        """
        #expect(try validRNC(rnc, "<root xmlns:p=\"urn:x\"><p:anything/></root>"))
        #expect(try !validRNC(rnc, "<root xmlns:q=\"urn:y\"><q:anything/></root>"))
    }

    @Test("RNC ns:* - name subtracts a name from the namespace wildcard")
    func test_rncNsWildcardExcept() throws {
        let rnc = """
        namespace p = "urn:x"
        element root { element p:* - p:skip { empty } }
        """
        #expect(try validRNC(rnc, "<root xmlns:p=\"urn:x\"><p:keep/></root>"))
        #expect(try !validRNC(rnc, "<root xmlns:p=\"urn:x\"><p:skip/></root>"))
    }
}
