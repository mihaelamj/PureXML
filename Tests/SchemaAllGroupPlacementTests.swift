@testable import PureXML
import Testing

@Suite("XSD all-group placement (cos-all-limited)")
struct SchemaAllGroupPlacementTests {
    private let xsd = "xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""

    private func compiles(_ body: String) -> Bool {
        (try? PureXML.Schema.Document("<xs:schema \(xsd)>\(body)</xs:schema>")) != nil
    }

    @Test("An all-group referenced inside a compositor is rejected; as the whole content it compiles")
    func test_allGroupReferencePlacement() {
        let allGroup = "<xs:group name=\"g\"><xs:all><xs:element name=\"a\"/></xs:all></xs:group>"
        // Referenced inside a sequence: the all is not the whole content model.
        #expect(!compiles(allGroup + "<xs:complexType name=\"T\"><xs:sequence>"
                + "<xs:element name=\"b\"/><xs:group ref=\"g\"/></xs:sequence></xs:complexType>"))
        // Referenced inside a choice: likewise rejected.
        #expect(!compiles(allGroup + "<xs:complexType name=\"T\"><xs:choice>"
                + "<xs:group ref=\"g\"/></xs:choice></xs:complexType>"))
        // Referenced as the whole content model: valid.
        #expect(compiles(allGroup + "<xs:complexType name=\"T\"><xs:group ref=\"g\"/></xs:complexType>"))
    }

    @Test("A non-all group referenced inside a compositor is fine")
    func test_nonAllGroupReferenceAccepted() {
        let group = "<xs:group name=\"g\"><xs:sequence><xs:element name=\"a\"/></xs:sequence></xs:group>"
        #expect(compiles(group + "<xs:complexType name=\"T\"><xs:sequence>"
                + "<xs:group ref=\"g\"/></xs:sequence></xs:complexType>"))
    }

    /// An imported namespace may define an all-group whose local name collides with
    /// a *non-all* group in this schema's own target namespace. A reference to the
    /// local group inside a compositor resolves to this target namespace and is
    /// therefore valid: the all-group lives in a different namespace and is not the
    /// referent. All-group names are tracked per defining namespace, so the
    /// collision must not cause the valid local reference to be rejected.
    @Test("An imported all-group does not shadow a same-named local non-all group")
    func test_importedAllGroupDoesNotShadowLocalNonAll() {
        let imported = "<xs:schema \(xsd) targetNamespace=\"urn:imp\">"
            + "<xs:group name=\"g\"><xs:all><xs:element name=\"a\"/></xs:all></xs:group>"
            + "</xs:schema>"
        let main = "<xs:schema \(xsd) targetNamespace=\"urn:main\" xmlns=\"urn:main\" xmlns:imp=\"urn:imp\">"
            + "<xs:import namespace=\"urn:imp\" schemaLocation=\"imp.xsd\"/>"
            + "<xs:group name=\"g\"><xs:sequence><xs:element name=\"x\"/></xs:sequence></xs:group>"
            + "<xs:complexType name=\"T\"><xs:sequence><xs:group ref=\"g\"/></xs:sequence></xs:complexType>"
            + "</xs:schema>"
        let document = try? PureXML.Schema.Document(main, schemaLoader: { $0 == "imp.xsd" ? imported : nil })
        #expect(document != nil)
    }
}
