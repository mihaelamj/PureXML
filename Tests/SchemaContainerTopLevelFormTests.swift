import Testing
@testable import PureXML

/// The top-level (global) declaration constraints apply to every document in a
/// schema composition, not only the one being compiled. The `form` attribute is
/// permitted only on a LOCAL element or attribute declaration; a global one that
/// carries it is invalid (XSD 1.0 schema-for-schemas: `topLevelAttribute` and
/// `topLevelElement` have no `form`). When the offending declaration lives in an
/// included or imported document the check used to be skipped, so the schema was
/// wrongly accepted. Mirrors XSTS attQ016 (import) and attQ018 (include).
@Suite("global form in included/imported documents")
struct SchemaContainerTopLevelFormTests {
    private func compiles(_ main: String, _ files: [String: String]) -> Bool {
        (try? PureXML.Schema.Document(main, schemaLoader: { files[$0] })) != nil
    }

    private let main = """
    <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                targetNamespace="urn:t" xmlns:t="urn:t">
      <xsd:include schemaLocation="lib.xsd"/>
      <xsd:element name="doc" type="xsd:string"/>
    </xsd:schema>
    """

    @Test("an included document with form on a global attribute is rejected")
    func test_includedGlobalAttributeForm() {
        let lib = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xsd:attribute name="ga" form="qualified"/>
        </xsd:schema>
        """
        #expect(!compiles(main, ["lib.xsd": lib]))
    }

    @Test("an included document with form on a global element is rejected")
    func test_includedGlobalElementForm() {
        let lib = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xsd:element name="ge" form="qualified" type="xsd:string"/>
        </xsd:schema>
        """
        #expect(!compiles(main, ["lib.xsd": lib]))
    }

    @Test("the same global attribute without form keeps the composition valid")
    func test_includedGlobalAttributeNoForm() {
        let lib = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:t">
          <xsd:attribute name="ga" type="xsd:string"/>
        </xsd:schema>
        """
        #expect(compiles(main, ["lib.xsd": lib]))
    }

    @Test("an imported document with form on a global attribute is rejected")
    func test_importedGlobalAttributeForm() {
        let importer = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema"
                    targetNamespace="urn:t" xmlns:t="urn:t">
          <xsd:import namespace="urn:i" schemaLocation="imp.xsd"/>
          <xsd:element name="doc" type="xsd:string"/>
        </xsd:schema>
        """
        let imp = """
        <xsd:schema xmlns:xsd="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:i">
          <xsd:attribute name="ia" form="qualified"/>
        </xsd:schema>
        """
        #expect(!compiles(importer, ["imp.xsd": imp]))
    }
}
