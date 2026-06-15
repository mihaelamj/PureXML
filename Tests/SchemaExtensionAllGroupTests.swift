@testable import PureXML
import Testing

@Suite("XSD all-group in extension (cos-all-limited.1.2 via extension)")
struct SchemaExtensionAllGroupTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    private func ext(base: String, content: String) -> String {
        "<xs:complexType name=\"fooType\"><xs:complexContent>"
            + "<xs:extension base=\"\(base)\">\(content)</xs:extension>"
            + "</xs:complexContent></xs:complexType>"
    }

    private let seqBase = "<xs:complexType name=\"myType\"><xs:sequence>"
        + "<xs:element name=\"a\" type=\"xs:string\"/></xs:sequence></xs:complexType>"
    private let emptyBase = "<xs:complexType name=\"emptyType\"><xs:attribute name=\"x\" type=\"xs:string\"/></xs:complexType>"
    private let allContent = "<xs:all><xs:element name=\"b\" type=\"xs:string\"/></xs:all>"

    @Test("An all group extending a base with content is rejected")
    func test_allExtendingContentRejected() {
        #expect(!compiles(seqBase + ext(base: "myType", content: allContent)))
    }

    @Test("An all group extending an empty base compiles")
    func test_allExtendingEmptyAccepted() {
        #expect(compiles(emptyBase + ext(base: "emptyType", content: allContent)))
    }

    @Test("A sequence extension of a content base compiles")
    func test_sequenceExtensionAccepted() {
        #expect(compiles(seqBase + ext(base: "myType", content: "<xs:sequence><xs:element name=\"b\" type=\"xs:string\"/></xs:sequence>")))
    }

    @Test("An all group as the whole content of a complex type compiles")
    func test_allAsWholeContentAccepted() {
        #expect(compiles("<xs:complexType name=\"t\">\(allContent)</xs:complexType>"))
    }

    /// A base whose content is an explicit but empty model group (`<xs:sequence/>`)
    /// has effectively empty content, so extending it with an `all` makes the `all`
    /// the whole content model, which is valid (W3C Bug 6202).
    @Test("An all group extending an explicitly-empty (non-mixed) base compiles")
    func test_allExtendingExplicitEmptyAccepted() {
        let base = "<xs:complexType name=\"emptyGroup\"><xs:sequence/></xs:complexType>"
        #expect(compiles(base + ext(base: "emptyGroup", content: allContent)))
    }

    /// A mixed base, even with an empty particle, may not be extended by an `all`
    /// (the resolution of W3C Bug 6202 keeps this invalid).
    @Test("An all group extending a mixed empty base is rejected")
    func test_allExtendingMixedEmptyRejected() {
        let base = "<xs:complexType name=\"mixedEmpty\" mixed=\"true\"><xs:sequence/></xs:complexType>"
        #expect(!compiles(base + ext(base: "mixedEmpty", content: allContent)))
    }
}
