@testable import PureXML
import Testing

/// The instance-validity derivation/substitution subsystem keys its `block`,
/// abstract-type, and derivation-backbone tables by namespaced identity
/// (`{ns}local`), so two complex types sharing a local name in different
/// namespaces do not collide. Without this, a `blockDefault` in one namespace
/// would wrongly block an `xsi:type` substitution among the same-named types of
/// another namespace (a false rejection).
@Suite("namespaced derivation keys do not cross-block")
struct SchemaNamespacedDerivationTests {
    /// Schema A (`urn:a`, `blockDefault="#all"`) imports schema B (`urn:b`, no
    /// block). Both declare a complex type `T`, a `TD` extending their own `T`, and
    /// an element `e` typed by their own `T`.
    private let schemaA = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
               targetNamespace="urn:a" xmlns:a="urn:a" blockDefault="#all">
      <xs:import namespace="urn:b" schemaLocation="b.xsd"/>
      <xs:complexType name="T"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
      <xs:complexType name="TD">
        <xs:complexContent><xs:extension base="a:T"><xs:sequence><xs:element name="y" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
      </xs:complexType>
      <xs:element name="e" type="a:T"/>
    </xs:schema>
    """

    private let schemaB = """
    <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:b" xmlns:b="urn:b">
      <xs:complexType name="T"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
      <xs:complexType name="TD">
        <xs:complexContent><xs:extension base="b:T"><xs:sequence><xs:element name="y" type="xs:string"/></xs:sequence></xs:extension></xs:complexContent>
      </xs:complexType>
      <xs:element name="e" type="b:T"/>
    </xs:schema>
    """

    private var loader: (String) -> String? {
        let schemaB = schemaB
        return { $0 == "b.xsd" ? schemaB : nil }
    }

    @Test("an extension xsi:type in urn:b is not blocked by urn:a's blockDefault")
    func test_otherNamespaceNotBlocked() throws {
        let document = try PureXML.Schema.Document(schemaA, schemaLoader: loader)
        let instance = """
        <b:e xmlns:b="urn:b" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:type="b:TD"><x>a</x><y>b</y></b:e>
        """
        #expect(try document.validate(instance, schemaLoader: loader).isEmpty)
    }

    @Test("the same extension xsi:type in urn:a IS blocked by its own blockDefault")
    func test_ownNamespaceBlocked() throws {
        let document = try PureXML.Schema.Document(schemaA, schemaLoader: loader)
        let instance = """
        <a:e xmlns:a="urn:a" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
             xsi:type="a:TD"><x>a</x><y>b</y></a:e>
        """
        #expect(try !document.validate(instance, schemaLoader: loader).isEmpty)
    }
}
