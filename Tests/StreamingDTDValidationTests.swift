@testable import PureXML
import Testing

@Suite("Streaming DTD validation")
struct StreamingDTDValidationTests {
    /// Builds a DTD schema from an internal subset by parsing a carrier document.
    private func schema(_ dtd: String) throws -> PureXML.Validation.DTDSchema {
        let carrier = "<!DOCTYPE root [\(dtd)]><root/>"
        let parsed = try PureXML.Parsing.Parser().parseWithDocumentType(carrier, limits: .init(allowDoctype: true))
        return PureXML.Validation.DTDSchema(parsed.documentType)
    }

    @Test("A valid document streams with no errors")
    func test_valid() throws {
        let dtd = try schema("<!ELEMENT list (item+)><!ELEMENT item (#PCDATA)>")
        let errors = try PureXML.validate(streaming: "<list><item>a</item><item>b</item></list>", dtd: dtd)
        #expect(errors.isEmpty)
    }

    @Test("A child outside the content model is reported, located at the parent")
    func test_strayChild() throws {
        let dtd = try schema("<!ELEMENT list (item+)><!ELEMENT item (#PCDATA)><!ELEMENT wrong (#PCDATA)>")
        let errors = try PureXML.validate(streaming: "<list><wrong/></list>", dtd: dtd)
        let failure = try #require(errors.first)
        #expect(failure.reason.contains("<wrong>"))
        #expect(failure.codingPath.map(\.stringValue) == ["list"])
    }

    @Test("A missing required attribute is reported as each element closes")
    func test_requiredAttribute() throws {
        let dtd = try schema("<!ELEMENT list (item+)><!ELEMENT item (#PCDATA)><!ATTLIST item id CDATA #REQUIRED>")
        let errors = try PureXML.validate(streaming: "<list><item>a</item></list>", dtd: dtd)
        #expect(errors.contains { $0.reason.contains("id") })
    }

    @Test("A duplicate ID is reported and a forward IDREF resolves at finish")
    func test_idAndIdref() throws {
        let dtd = try schema(
            "<!ELEMENT root (a*)><!ELEMENT a EMPTY><!ATTLIST a id ID #IMPLIED ref IDREF #IMPLIED>",
        )
        // A duplicate ID.
        let dupes = try PureXML.validate(streaming: "<root><a id=\"x\"/><a id=\"x\"/></root>", dtd: dtd)
        #expect(dupes.contains { $0.reason.contains("duplicate ID 'x'") })
        // A forward IDREF (the id appears after the ref) resolves with no error.
        #expect(try PureXML.validate(streaming: "<root><a ref=\"y\"/><a id=\"y\"/></root>", dtd: dtd).isEmpty)
        // A dangling IDREF is reported.
        let dangling = try PureXML.validate(streaming: "<root><a ref=\"z\"/></root>", dtd: dtd)
        #expect(dangling.contains { $0.reason.contains("IDREF 'z'") })
    }

    @Test("Streaming validation agrees with tree validation on the same document")
    func test_matchesTreeValidation() throws {
        let internalSubset = "<!ELEMENT list (item+)><!ELEMENT item (#PCDATA)><!ATTLIST item id ID #IMPLIED>"
        let doc = """
        <!DOCTYPE list [\(internalSubset)]>
        <list><item id="d">a</item><stray/><item id="d">b</item></list>
        """
        let tree = try PureXML.validateAgainstInternalDTD(doc)
        let dtd = try schema(internalSubset)
        let body = "<list><item id=\"d\">a</item><stray/><item id=\"d\">b</item></list>"
        let streamed = try PureXML.validate(streaming: body, dtd: dtd)
        // Same problems surface (the reasons match; the streamed path always indexes).
        #expect(streamed.map(\.reason).sorted() == tree.map(\.reason).sorted())
        #expect(!streamed.isEmpty)
    }
}
