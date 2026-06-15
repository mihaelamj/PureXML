@testable import PureXML
import Testing

@Suite("XSD top-level group applicability (topLevelGroup)")
struct SchemaTopLevelGroupTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("A top-level group with ref/minOccurs/maxOccurs is rejected")
    func test_topLevelForbiddenRejected() {
        #expect(!compiles("<xs:group ref=\"g\"/>"))
        #expect(!compiles("<xs:group name=\"g\" minOccurs=\"1\"><xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:group>"))
        #expect(!compiles("<xs:group name=\"g\" maxOccurs=\"5\"><xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:group>"))
    }

    @Test("A top-level group in redefine with minOccurs/maxOccurs is rejected")
    func test_redefineForbiddenRejected() {
        let baseRed = "<xs:group name=\"X\"><xs:sequence><xs:element name=\"a\"/></xs:sequence></xs:group>"
        let loader: (String) -> String? = { $0 == "base.xsd" ? "<xs:schema \(xsd)>\(baseRed)</xs:schema>" : nil }

        let redefineMin = """
        <xs:redefine schemaLocation="base.xsd">
          <xs:group name="X" minOccurs="1">
            <xs:sequence><xs:group ref="X"/><xs:element name="b"/></xs:sequence>
          </xs:group>
        </xs:redefine>
        """
        #expect((try? PureXML.Schema.Document("<xs:schema \(xsd)>\(redefineMin)</xs:schema>", schemaLoader: loader)) == nil)
    }

    @Test("A plain top-level group declaration compiles")
    func test_plainTopLevelAccepted() {
        #expect(compiles("<xs:group name=\"g\"><xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:group>"))
    }

    @Test("A local group ref with occurrence compiles")
    func test_localParticleAccepted() {
        #expect(compiles(
            "<xs:group name=\"g\"><xs:sequence><xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:group>"
                + "<xs:element name=\"e\"><xs:complexType><xs:sequence>"
                + "<xs:group ref=\"g\" minOccurs=\"0\" maxOccurs=\"3\"/>"
                + "</xs:sequence></xs:complexType></xs:element>",
        ))
    }
}
