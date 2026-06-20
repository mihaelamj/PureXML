import Testing
@testable import PureXML

/// src-resolve on the cross-document skip path (#185): when a schema declares
/// imports but no external document is loaded (no `schemaLocation`, or it does not
/// resolve), the full pool-based resolution stands down. A reference into an
/// *imported* namespace must still stand down (its components may live in the
/// unloaded document), but a reference into a namespace that is never imported can
/// resolve nowhere under any loading and is unresolvable. Mirrors corpus schZ011.
@Suite("XSD foreign-namespace reference resolvability (#185)")
struct SchemaForeignNamespaceReferenceTests {
    private func compiles(_ schema: String) -> Bool {
        (try? PureXML.Schema.Document(schema)) != nil
    }

    @Test("schZ011 shape: a reference into a never-imported namespace is rejected")
    func test_unimportedNamespaceReferenceRejected() {
        // imports a/b/c (no schemaLocation), references d:d where d is never imported.
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:a="a" xmlns:b="b" xmlns:c="c" xmlns:d="d">
          <xs:import namespace="a"/>
          <xs:import namespace="b"/>
          <xs:import namespace="c"/>
          <xs:complexType name="uType">
            <xs:sequence>
              <xs:element ref="a:a"/>
              <xs:element ref="b:b"/>
              <xs:element ref="c:c"/>
              <xs:element ref="d:d"/>
            </xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        #expect(!compiles(schema), "d:d names an un-imported namespace and must be rejected")
    }

    @Test("lenient guard: references into imported-but-unloaded namespaces stand down")
    func test_importedUnloadedNamespaceReferenceAccepted() {
        // Same shape without the offending d:d: every foreign reference is into an
        // imported namespace whose document was not loaded, so it must not be flagged.
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:a="a" xmlns:b="b" xmlns:c="c">
          <xs:import namespace="a"/>
          <xs:import namespace="b"/>
          <xs:import namespace="c"/>
          <xs:complexType name="uType">
            <xs:sequence>
              <xs:element ref="a:a"/>
              <xs:element ref="b:b"/>
              <xs:element ref="c:c"/>
            </xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        #expect(compiles(schema), "imported-but-unloaded references must remain lenient")
    }

    @Test("schZ004 shape on the skip path: a located (unloaded) import keeps the check lenient")
    func test_locatedUnloadedImportStandsDown() {
        // Mirrors corpus schZ004 (W3C: valid): the main doc imports only `a` (with a
        // schemaLocation), and references `b:b`. Namespace `b` is reachable transitively
        // because `a`'s document imports it. When that document does not load, the import
        // closure is unknown, so `b:b` must NOT be flagged. Compiled with no loader, so
        // the located import fails to resolve and the skip path is taken.
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="main" xmlns:m="main" xmlns:a="a" xmlns:b="b">
          <xs:import namespace="a" schemaLocation="schZ004a.xsd"/>
          <xs:complexType name="ct">
            <xs:sequence>
              <xs:element name="a" type="a:a"/>
              <xs:element name="b" type="b:b"/>
            </xs:sequence>
          </xs:complexType>
        </xs:schema>
        """
        #expect(compiles(schema), "b:b is transitively resolvable; an unloaded located import must stay lenient")
    }

    @Test("a foreign type reference into a never-imported namespace is also rejected")
    func test_unimportedTypeReferenceRejected() {
        let schema = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   xmlns:a="a" xmlns:z="z">
          <xs:import namespace="a"/>
          <xs:element name="e" type="z:t"/>
        </xs:schema>
        """
        #expect(!compiles(schema), "z:t names an un-imported namespace and must be rejected")
    }
}
