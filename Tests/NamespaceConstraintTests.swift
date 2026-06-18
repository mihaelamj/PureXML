import Testing
@testable import PureXML

/// The Namespaces 1.0 constraints (#136): reserved prefixes and namespace
/// names, qualified-name shape, duplicate expanded-name attributes, NCName
/// rules for PI targets and entity/notation names, and DTD-typed
/// normalization of binding values.
@Suite("Namespace constraints")
struct NamespaceConstraintTests {
    private func rejects(_ xml: String) -> Bool {
        (try? PureXML.parse(xml, limits: .init(allowDoctype: true))) == nil
    }

    @Test("Malformed qualified names are rejected")
    func test_qualifiedNameShape() {
        #expect(rejects("<foo: />"))
        #expect(rejects("<:foo />"))
        #expect(rejects("<a:b:c xmlns:a=\"urn:x\"/>"))
        #expect(rejects("<foo xmlns:=\"urn:x\"/>"))
        #expect(!rejects("<a:b xmlns:a=\"urn:x\"/>"))
    }

    @Test("Reserved prefixes and namespace names are protected")
    func test_reservedBindings() {
        #expect(rejects("<f xmlns:xml=\"urn:wrong\"/>"))
        #expect(!rejects("<f xmlns:xml=\"http://www.w3.org/XML/1998/namespace\"/>"))
        #expect(rejects("<f xmlns:yml=\"http://www.w3.org/XML/1998/namespace\"/>"))
        #expect(rejects("<f xmlns:xmlns=\"http://www.w3.org/2000/xmlns/\"/>"))
        #expect(rejects("<f xmlns:xmlns=\"urn:other\"/>"))
        #expect(rejects("<f xmlns:ymlns=\"http://www.w3.org/2000/xmlns/\"/>"))
        #expect(rejects("<f xmlns=\"http://www.w3.org/XML/1998/namespace\"/>"))
        #expect(rejects("<f xmlns=\"http://www.w3.org/2000/xmlns/\"/>"))
    }

    @Test("A prefix may not be undeclared in Namespaces 1.0")
    func test_noPrefixUndeclaration() {
        #expect(rejects("<f xmlns:a=\"\"/>"))
        #expect(!rejects("<f xmlns=\"\"/>"))
    }

    @Test("Attributes must be distinct by expanded name")
    func test_duplicateExpandedNames() {
        let xml = "<f xmlns:a=\"urn:x\" xmlns:b=\"urn:x\"><g a:attr=\"1\" b:attr=\"2\"/></f>"
        #expect(rejects(xml))
        let distinct = "<f xmlns:a=\"urn:x\" xmlns:b=\"urn:y\"><g a:attr=\"1\" b:attr=\"2\"/></f>"
        #expect(!rejects(distinct))
    }

    @Test("PI targets and entity/notation names are NCNames")
    func test_ncNames() {
        #expect(rejects("<?a:b data?>\n<f/>"))
        #expect(rejects("<!DOCTYPE f [<!ELEMENT f ANY><!ENTITY a:b \"x\">]>\n<f/>"))
        #expect(rejects("<!DOCTYPE f [<!ELEMENT f ANY><!NOTATION a:b SYSTEM \"n\">]>\n<f/>"))
    }

    @Test("A DTD-typed xmlns value binds its normalized form")
    func test_typedBindingNormalization() {
        let xml = """
        <!DOCTYPE f [
        <!ELEMENT f ANY><!ELEMENT g ANY>
        <!ATTLIST f xmlns:a CDATA #IMPLIED xmlns:b NMTOKEN #IMPLIED>
        <!ATTLIST g a:attr CDATA #IMPLIED b:attr CDATA #IMPLIED>
        ]>
        <f xmlns:a="urn:xyzzy" xmlns:b=" urn:xyzzy ">
        <g a:attr="1" b:attr="2"/>
        </f>
        """
        #expect(rejects(xml))
    }
}
