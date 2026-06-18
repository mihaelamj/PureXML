import Testing
@testable import PureXML

@Suite("Canonical XML 2.0: sequential prefix rewrite and QName-aware values")
struct CanonicalPrefixRewriteTests {
    private func c14n(_ xml: String, _ options: PureXML.Canonical.Options) throws -> String {
        try PureXML.Canonical.canonicalize(PureXML.parse(xml), options: options)
    }

    private let sequential = PureXML.Canonical.Options(prefixRewrite: .sequential)

    @Test("Sequential rewrite renames a prefix to n0 and declares it at first use")
    func test_basicRewrite() throws {
        #expect(try c14n("<r xmlns:p=\"urn:x\"><p:c/></r>", sequential) == "<r><n0:c xmlns:n0=\"urn:x\"></n0:c></r>")
    }

    @Test("Documents differing only in prefix spelling canonicalize identically")
    func test_prefixIndependence() throws {
        let withP = try c14n("<r xmlns:p=\"urn:x\"><p:c/></r>", sequential)
        let withQ = try c14n("<r xmlns:q=\"urn:x\"><q:c/></r>", sequential)
        #expect(withP == withQ)
    }

    @Test("The default namespace is given a canonical prefix")
    func test_defaultNamespaceRewritten() throws {
        #expect(try c14n("<a xmlns=\"urn:d\"><b/></a>", sequential) == "<n0:a xmlns:n0=\"urn:d\"><n0:b></n0:b></n0:a>")
    }

    @Test("Prefixes are numbered in document order of first use")
    func test_documentOrderNumbering() throws {
        let xml = "<r xmlns:b=\"urn:b\" xmlns:a=\"urn:a\"><b:x/><a:y/></r>"
        // urn:b is used first (by <b:x>), so it becomes n0; urn:a becomes n1.
        #expect(try c14n(xml, sequential) == "<r><n0:x xmlns:n0=\"urn:b\"></n0:x><n1:y xmlns:n1=\"urn:a\"></n1:y></r>")
    }

    @Test("A QName-aware attribute value has its prefix rewritten too")
    func test_qnameAwareAttribute() throws {
        let options = PureXML.Canonical.Options(
            prefixRewrite: .sequential,
            qnameAwareLabels: [.init(localName: "type")],
        )
        // <e type="p:T"> with p bound to urn:x: type becomes the canonical prefix.
        let output = try c14n("<r xmlns:p=\"urn:x\"><p:e type=\"p:T\"/></r>", options)
        #expect(output == "<r><n0:e xmlns:n0=\"urn:x\" type=\"n0:T\"></n0:e></r>")
    }

    @Test("Retain (the default) leaves prefixes untouched")
    func test_retainDefault() throws {
        #expect(try c14n("<r xmlns:p=\"urn:x\"><p:c/></r>", .inclusive) == "<r xmlns:p=\"urn:x\"><p:c></p:c></r>")
    }
}
