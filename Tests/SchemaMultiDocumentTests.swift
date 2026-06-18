import Testing
@testable import PureXML

/// `validate(_:schemaLoader:)` honors an instance's `xsi:schemaLocation`,
/// loading the referenced schema documents so a strict (or lax) wildcard can
/// resolve elements declared in another document (#147, XSTS particles set).
@Suite("Multi-document validation via xsi:schemaLocation")
struct SchemaMultiDocumentTests {
    private let mainXSD = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
               targetNamespace="urn:a" xmlns:a="urn:a">
      <xs:element name="doc">
        <xs:complexType>
          <xs:sequence>
            <xs:any namespace="##other" processContents="strict" minOccurs="1" maxOccurs="3"/>
          </xs:sequence>
        </xs:complexType>
      </xs:element>
    </xs:schema>
    """

    private let otherXSD = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:b">
      <xs:element name="thing" type="xs:int"/>
    </xs:schema>
    """

    private let instance = """
    <a:doc xmlns:a="urn:a" xmlns:b="urn:b"
           xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
           xsi:schemaLocation="urn:b other.xsd"><b:thing>5</b:thing></a:doc>
    """

    @Test("A strict wildcard resolves an element from the xsi:schemaLocation schema")
    func test_resolvesAcrossDocuments() throws {
        let doc = try PureXML.Schema.Document(mainXSD)
        let loader: (String) -> String? = { [otherXSD] in $0 == "other.xsd" ? otherXSD : nil }
        #expect(try doc.validate(instance, schemaLoader: loader).isEmpty)
    }

    @Test("The loaded declaration's type is still enforced")
    func test_loadedTypeEnforced() throws {
        let doc = try PureXML.Schema.Document(mainXSD)
        let loader: (String) -> String? = { [otherXSD] in $0 == "other.xsd" ? otherXSD : nil }
        let bad = instance.replacingOccurrences(of: "<b:thing>5</b:thing>", with: "<b:thing>notint</b:thing>")
        #expect(try !doc.validate(bad, schemaLoader: loader).isEmpty)
    }

    @Test("Without the loader a strict wildcard cannot resolve the element")
    func test_strictUnresolvedWithoutLoader() throws {
        let doc = try PureXML.Schema.Document(mainXSD)
        #expect(try !doc.validate(instance).isEmpty)
    }

    @Test("Streaming validation honors xsi:schemaLocation the same as the tree path")
    func test_streamingResolvesAcrossDocuments() throws {
        let doc = try PureXML.Schema.Document(mainXSD)
        let loader: (String) -> String? = { [otherXSD] in $0 == "other.xsd" ? otherXSD : nil }
        let tree = try doc.validate(instance, schemaLoader: loader).map(\.reason).sorted()
        let streamed = try doc.validate(streaming: instance, schemaLoader: loader).map(\.reason).sorted()
        #expect(tree == streamed)
        #expect(tree.isEmpty)
    }

    @Test("Streaming strict wildcard fails without the loader")
    func test_streamingStrictUnresolvedWithoutLoader() throws {
        let doc = try PureXML.Schema.Document(mainXSD)
        #expect(try !doc.validate(streaming: instance).isEmpty)
    }
}
