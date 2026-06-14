@testable import PureXML
import Testing

@Suite("XSD circular type derivation")
struct SchemaCircularDerivationTests {
    private let header = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"

    private func compiles(_ body: String, loader: @escaping (String) -> String? = { _ in nil }) -> Bool {
        (try? PureXML.Schema.Document(header + body + "</xs:schema>", schemaLoader: loader)) != nil
    }

    @Test("A type derived from itself is rejected (ct-props-correct.3 / st-props-correct.2)")
    func test_selfDerivationRejected() {
        // A complex type extending itself (addB101).
        #expect(!compiles(
            "<xs:complexType name=\"A\"><xs:complexContent><xs:extension base=\"A\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>",
        ))
        // A complex type restricting itself.
        #expect(!compiles(
            "<xs:complexType name=\"A\"><xs:complexContent><xs:restriction base=\"A\"><xs:sequence/></xs:restriction></xs:complexContent></xs:complexType>",
        ))
        // A mutual derivation cycle A -> B -> A.
        #expect(!compiles(
            "<xs:complexType name=\"A\"><xs:complexContent><xs:extension base=\"B\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>"
                + "<xs:complexType name=\"B\"><xs:complexContent><xs:extension base=\"A\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>",
        ))
        // A simpleType restriction cycle s0 -> s1 -> s0.
        #expect(!compiles(
            "<xs:simpleType name=\"s0\"><xs:restriction base=\"s1\"/></xs:simpleType>"
                + "<xs:simpleType name=\"s1\"><xs:restriction base=\"s0\"/></xs:simpleType>",
        ))
    }

    @Test("Recursive element content and normal derivation are not cycles")
    func test_recursionAndNormalDerivationAccepted() {
        // A type containing an element of its own type is a recursive data structure,
        // not a derivation cycle: only the base chain is a cycle, element content is
        // not. (Must compile.)
        #expect(compiles(
            "<xs:complexType name=\"node\"><xs:sequence><xs:element name=\"child\" type=\"node\" minOccurs=\"0\"/></xs:sequence></xs:complexType>"
                + "<xs:element name=\"root\" type=\"node\"/>",
        ))
        // Deriving from a ur-type terminates the chain (the schema-for-schemas case).
        #expect(compiles(
            "<xs:complexType name=\"A\"><xs:complexContent><xs:extension base=\"xs:anyType\"><xs:sequence/></xs:extension></xs:complexContent></xs:complexType>",
        ))
        // A normal restriction chain A -> base -> xs:string.
        #expect(compiles(
            "<xs:simpleType name=\"a\"><xs:restriction base=\"b\"/></xs:simpleType>"
                + "<xs:simpleType name=\"b\"><xs:restriction base=\"xs:string\"/></xs:simpleType>",
        ))
    }

    @Test("A type whose base is a same-local-name type in another namespace is not a cycle")
    func test_crossNamespaceSameLocalNameAccepted() {
        // local:X extends the entirely different foreign:X. Resolving by local name
        // would falsely report a self-cycle; the namespace-aware walk follows only
        // a base in this schema's own target namespace, so the foreign base ends the
        // chain. (Must compile.)
        let schema = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\""
            + " xmlns:ns=\"urn:foreign\" targetNamespace=\"urn:local\" xmlns=\"urn:local\">"
            + "<xs:import namespace=\"urn:foreign\"/>"
            + "<xs:complexType name=\"X\"><xs:complexContent><xs:extension base=\"ns:X\">"
            + "<xs:sequence/></xs:extension></xs:complexContent></xs:complexType></xs:schema>"
        #expect((try? PureXML.Schema.Document(schema)) != nil)
    }

    @Test("Circular model-group, attribute-group, and substitution-group references are rejected")
    func test_referenceCyclesRejected() {
        // A model group that directly contains itself (mg-props-correct.2).
        #expect(!compiles(
            "<xs:group name=\"g\"><xs:sequence><xs:group ref=\"g\"/></xs:sequence></xs:group>"
                + "<xs:element name=\"r\"><xs:complexType><xs:group ref=\"g\"/></xs:complexType></xs:element>",
        ))
        // An attribute-group reference cycle a -> b -> a (ag-props-correct.3).
        #expect(!compiles(
            "<xs:attributeGroup name=\"a\"><xs:attributeGroup ref=\"b\"/></xs:attributeGroup>"
                + "<xs:attributeGroup name=\"b\"><xs:attributeGroup ref=\"a\"/></xs:attributeGroup>",
        ))
        // A substitution-group affiliation loop x -> y -> x (e-props-correct.6).
        #expect(!compiles(
            "<xs:element name=\"x\" substitutionGroup=\"y\"/><xs:element name=\"y\" substitutionGroup=\"x\"/>",
        ))
    }

    @Test("A group recursing through an element, and a substitution chain, are allowed")
    func test_groupRecursionAndChainAccepted() {
        // particlesZ010: a group referenced inside an element's content is a recursive
        // data structure, not a group containing itself. (Must compile.)
        #expect(compiles(
            "<xs:group name=\"g\"><xs:sequence><xs:element name=\"e\">"
                + "<xs:complexType><xs:sequence><xs:group ref=\"g\" minOccurs=\"0\"/></xs:sequence></xs:complexType>"
                + "</xs:element></xs:sequence></xs:group>"
                + "<xs:element name=\"r\"><xs:complexType><xs:group ref=\"g\"/></xs:complexType></xs:element>",
        ))
        // A non-cyclic substitution chain leaf -> mid -> head.
        #expect(compiles(
            "<xs:element name=\"head\"/><xs:element name=\"mid\" substitutionGroup=\"head\"/>"
                + "<xs:element name=\"leaf\" substitutionGroup=\"mid\"/>",
        ))
    }

    @Test("A type redefining itself is allowed (the base names its former self)")
    func test_redefineSelfDerivationAccepted() {
        let base = "<xs:schema xmlns:xs=\"http://www.w3.org/2001/XMLSchema\">"
            + "<xs:complexType name=\"T\"><xs:sequence><xs:element name=\"x\" type=\"xs:string\"/></xs:sequence></xs:complexType>"
            + "</xs:schema>"
        let body = "<xs:redefine schemaLocation=\"base.xsd\">"
            + "<xs:complexType name=\"T\"><xs:complexContent><xs:restriction base=\"T\">"
            + "<xs:sequence><xs:element name=\"x\" type=\"xs:string\"/></xs:sequence>"
            + "</xs:restriction></xs:complexContent></xs:complexType></xs:redefine>"
            + "<xs:element name=\"r\" type=\"T\"/>"
        #expect(compiles(body, loader: { $0 == "base.xsd" ? base : nil }))
    }
}
