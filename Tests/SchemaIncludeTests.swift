@testable import PureXML
import Testing

@Suite("XSD include composition (#161)")
struct SchemaIncludeTests {
    @Test("chameleon include: no-namespace library merges into a target-namespace main schema")
    func test_chameleonIncludeWithTargetNamespace() throws {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string"><xs:pattern value="[A-Z]{3}"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        #expect(try doc.validate("<code xmlns=\"urn:main\">ABC</code>").isEmpty)
        #expect(try !doc.validate("<code xmlns=\"urn:main\">abc</code>").isEmpty)
    }

    /// src-redefine.5: a type inside xs:redefine must restrict/extend the type it
    /// redefines, which lives in the redefining schema's own target namespace. A base
    /// bound to a foreign namespace with the same local name (an imported type) is not
    /// self and is rejected; an unprefixed/own-namespace self-reference is valid.
    @Test("a redefined type must derive from itself, not a same-named foreign type")
    func test_redefineBaseMustBeSelfNamespace() {
        let redefined = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a">
          <xs:complexType name="T"><xs:sequence><xs:element name="x" type="xs:string"/></xs:sequence></xs:complexType>
        </xs:schema>
        """
        let imported = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:foo">
          <xs:complexType name="T"><xs:sequence/></xs:complexType>
        </xs:schema>
        """
        let loader: (String) -> String? = { $0 == "a.xsd" ? redefined : ($0 == "foo.xsd" ? imported : nil) }
        // Redefine of T whose extension base is foo:T (a foreign same-local-name type).
        let foreign = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a" xmlns:foo="urn:foo">
          <xs:import namespace="urn:foo" schemaLocation="foo.xsd"/>
          <xs:redefine schemaLocation="a.xsd">
            <xs:complexType name="T"><xs:complexContent><xs:extension base="foo:T">
              <xs:sequence><xs:element name="y" type="xs:string"/></xs:sequence>
            </xs:extension></xs:complexContent></xs:complexType>
          </xs:redefine>
        </xs:schema>
        """
        #expect((try? PureXML.Schema.Document(foreign, schemaLoader: loader)) == nil)
        // A proper self-redefine (base resolves to the redefining target namespace).
        let selfRedefine = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a" xmlns:a="urn:a">
          <xs:redefine schemaLocation="a.xsd">
            <xs:complexType name="T"><xs:complexContent><xs:extension base="a:T">
              <xs:sequence><xs:element name="y" type="xs:string"/></xs:sequence>
            </xs:extension></xs:complexContent></xs:complexType>
          </xs:redefine>
        </xs:schema>
        """
        #expect((try? PureXML.Schema.Document(selfRedefine, schemaLoader: loader)) != nil)
    }

    /// src-redefine.6.1.2: a group inside xs:redefine may reference itself, but that
    /// self-reference must occur exactly once (minOccurs = maxOccurs = 1). A
    /// self-reference with minOccurs="0" or maxOccurs="unbounded" is invalid; a unit
    /// self-reference (or absent occurrence, defaulting to 1) is valid.
    @Test("a redefined group's self-reference must occur exactly once")
    func test_redefineGroupSelfReferenceOccurrence() {
        let original = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a">
          <xs:group name="g"><xs:choice><xs:element name="x" type="xs:string"/></xs:choice></xs:group>
        </xs:schema>
        """
        let loader: (String) -> String? = { $0 == "a.xsd" ? original : nil }
        func redefine(_ selfRef: String) -> String {
            """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a" xmlns="urn:a">
              <xs:redefine schemaLocation="a.xsd">
                <xs:group name="g"><xs:choice><xs:element name="y" type="xs:string"/>\(selfRef)</xs:choice></xs:group>
              </xs:redefine>
            </xs:schema>
            """
        }
        // A non-unit self-reference is invalid.
        #expect((try? PureXML.Schema.Document(redefine(#"<xs:group ref="g" minOccurs="0"/>"#), schemaLoader: loader)) == nil)
        #expect((try? PureXML.Schema.Document(redefine(#"<xs:group ref="g" maxOccurs="unbounded"/>"#), schemaLoader: loader)) == nil)
        // A unit self-reference is valid.
        #expect((try? PureXML.Schema.Document(redefine(#"<xs:group ref="g"/>"#), schemaLoader: loader)) != nil)
    }

    /// src-redefine.7.2.1: a redefined attributeGroup may contain at most one
    /// self-reference; two references to the group being redefined are invalid.
    @Test("a redefined attributeGroup may have at most one self-reference")
    func test_redefineAttributeGroupSelfReferenceCount() {
        let original = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attributeGroup name="ag"><xs:attribute name="x" type="xs:string"/></xs:attributeGroup>
        </xs:schema>
        """
        let loader: (String) -> String? = { $0 == "a.xsd" ? original : nil }
        func redefine(_ refs: String) -> String {
            """
            <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
              <xs:redefine schemaLocation="a.xsd">
                <xs:attributeGroup name="ag"><xs:attribute name="y" type="xs:string"/>\(refs)</xs:attributeGroup>
              </xs:redefine>
            </xs:schema>
            """
        }
        // Two self-references are invalid; one is valid.
        #expect((try? PureXML.Schema.Document(redefine(#"<xs:attributeGroup ref="ag"/><xs:attributeGroup ref="ag"/>"#), schemaLoader: loader)) == nil)
        #expect((try? PureXML.Schema.Document(redefine(#"<xs:attributeGroup ref="ag"/>"#), schemaLoader: loader)) != nil)
    }

    /// src-resolve: when an include/import/redefine schemaLocation IS resolved (the
    /// loader returns content), that content must be a well-formed schema. Not-well-
    /// formed XML, or well-formed XML that is not an xs:schema, is rejected. A
    /// location the loader does not resolve (returns nil) is not an error.
    @Test("a resolved schemaLocation that is not a valid schema is rejected")
    func test_resolvedSchemaLocationMustBeSchema() {
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="bad.xsd"/>
        </xs:schema>
        """
        // Resolved to not-well-formed XML.
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "bad.xsd" ? "<not-well-formed" : nil })
        }
        // Resolved to well-formed XML that is not a schema.
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "bad.xsd" ? "<root><child/></root>" : nil })
        }
        // An UNRESOLVED location (loader returns nil) is not an error.
        #expect((try? PureXML.Schema.Document(main, schemaLoader: { _ in nil })) != nil)
    }

    /// src-import.3.1/3.2: an import's namespace attribute must equal the imported
    /// schema's targetNamespace (both equal, or both absent). Checked only when the
    /// schemaLocation resolves to a loaded schema.
    @Test("an import's namespace must match the imported targetNamespace")
    func test_importNamespaceMustMatchImportedTarget() {
        let mainNS = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:a" xmlns:b="urn:b">
          <xs:import namespace="urn:b" schemaLocation="b.xsd"/>
        </xs:schema>
        """
        // Imported doc's targetNamespace does NOT match the declared import namespace.
        let mismatched = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:WRONG\"/>"
        #expect((try? PureXML.Schema.Document(mainNS, schemaLoader: { $0 == "b.xsd" ? mismatched : nil })) == nil)
        // Imported doc has NO targetNamespace but the import declares one.
        let noTarget = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\"/>"
        #expect((try? PureXML.Schema.Document(mainNS, schemaLoader: { $0 == "b.xsd" ? noTarget : nil })) == nil)
        // Matching targetNamespace compiles.
        let matched = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\" targetNamespace=\"urn:b\"/>"
        #expect((try? PureXML.Schema.Document(mainNS, schemaLoader: { $0 == "b.xsd" ? matched : nil })) != nil)
        // An unresolved import (loader returns nil) is not an error.
        #expect((try? PureXML.Schema.Document(mainNS, schemaLoader: { _ in nil })) != nil)
    }

    @Test("xs:include with a mismatched targetNamespace is rejected")
    func test_invalidIncludeDifferentTargetNamespace() {
        let included = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:other">
          <xs:element name="e" type="xs:string"/>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="other.xsd"/>
          <xs:element name="root" type="xs:string"/>
        </xs:schema>
        """
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "other.xsd" ? included : nil })
        }
    }

    @Test("xs:include with matching targetNamespace is accepted")
    func test_includeMatchingTargetNamespace() throws {
        let included = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:simpleType name="sku">
            <xs:restriction base="xs:string"><xs:pattern value="[A-Z]{3}"/></xs:restriction>
          </xs:simpleType>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="code" type="sku"/>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? included : nil })
        #expect(try doc.validate("<code xmlns=\"urn:main\">ABC</code>").isEmpty)
    }

    @Test("chameleon include: attribute refs inside the included schema resolve after merge")
    func test_chameleonIncludeAttributeGroupRef() throws {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attribute name="a1" type="xs:string"/>
          <xs:attributeGroup name="g">
            <xs:attribute ref="a1"/>
          </xs:attributeGroup>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema"
                   targetNamespace="urn:main" xmlns="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
          <xs:element name="doc">
            <xs:complexType>
              <xs:attributeGroup ref="g"/>
            </xs:complexType>
          </xs:element>
        </xs:schema>
        """
        let doc = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        #expect(try doc.validate("<doc xmlns=\"urn:main\" a1=\"x\"/>").isEmpty)
    }

    @Test("undeclared refs inside an included chameleon schema are rejected at compile time")
    func test_invalidReferenceInsideIncludedSchema() {
        let library = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema">
          <xs:attributeGroup name="g">
            <xs:attribute ref="missing"/>
          </xs:attributeGroup>
        </xs:schema>
        """
        let main = """
        <xs:schema xmlns:xs="http://www.w3.org/2001/XMLSchema" targetNamespace="urn:main">
          <xs:include schemaLocation="lib.xsd"/>
        </xs:schema>
        """
        #expect(throws: Error.self) {
            _ = try PureXML.Schema.Document(main, schemaLoader: { $0 == "lib.xsd" ? library : nil })
        }
    }
}
